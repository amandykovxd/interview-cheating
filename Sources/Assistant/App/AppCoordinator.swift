import AppKit
import Foundation

/// Оркестратор. Подписывается на события, решает что с ними делать.
/// Деталей реализации сервисов не знает — только их протоколы.
@MainActor
final class AppCoordinator {
    private let di: DIContainer
    private let overlay: OverlayWindowController
    private let menuBar: MenuBarController

    private var audioTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?

    init(di: DIContainer) {
        self.di = di
        self.overlay = OverlayWindowController(viewModel: di.overlayViewModel)
        self.menuBar = MenuBarController()
    }

    func start() {
        wireMenuBar()
        wireHotkeys()
        startAudio()
        overlay.show()
        applyCaptureHiding()
        Log.app.info("coordinator started")
    }

    // MARK: - Проводка

    private func wireMenuBar() {
        menuBar.onToggleOverlay = { [weak self] in self?.overlay.toggle() }
        menuBar.onCaptureAndAsk = { [weak self] in self?.captureAndAsk() }
        menuBar.onQuit = { NSApp.terminate(nil) }
    }

    private func wireHotkeys() {
        di.hotkeys.onAction(.toggleOverlay) { [weak self] in self?.overlay.toggle() }
        di.hotkeys.onAction(.captureAndAsk) { [weak self] in self?.captureAndAsk() }
        di.hotkeys.start()
    }

    private func applyCaptureHiding() {
        overlay.window.setHiddenFromCapture(di.settings.hideOverlayFromCapture)
    }

    // MARK: - Аудио -> ASR -> контекст

    private func startAudio() {
        di.overlayViewModel.status = .listening
        do {
            let segments = try di.audioPipeline.start()
            audioTask = Task { [weak self] in
                for await segment in segments {
                    await self?.transcribe(segment)
                }
            }
        } catch {
            Log.audio.error("audio start failed: \(error.localizedDescription)")
            di.overlayViewModel.showError("Нет доступа к микрофону")
        }
    }

    private func transcribe(_ segment: AudioSegment) async {
        guard di.asrEngine.isAvailable else { return }
        for await result in di.asrEngine.transcribe(segment) {
            let ts = TranscriptSegment(
                source: segment.source,
                text: result.text,
                start: segment.start,
                end: segment.end,
                isFinal: result.isFinal,
                confidence: result.confidence
            )
            await di.contextManager.ingest(ts)
            if result.isFinal {
                di.overlayViewModel.lastTranscript = result.text
            }
        }
    }

    // MARK: - Хоткей: OCR + запрос к LLM

    private func captureAndAsk() {
        answerTask?.cancel()
        answerTask = Task { [weak self] in
            guard let self else { return }
            self.di.overlayViewModel.status = .thinking
            self.overlay.show()

            // снимаем область вокруг курсора (для MVP; выбор области — позже)
            if let rect = self.regionAroundCursor(),
               let ocr = await self.di.visionPipeline.recognizeRegion(rect) {
                await self.di.contextManager.ingest(ocr: ocr)
            }

            await self.streamAnswer(instruction: "Помоги с тем, что на экране и в разговоре.")
        }
    }

    private func streamAnswer(instruction: String) async {
        let snapshot = await di.contextManager.snapshot()
        let request = di.promptBuilder.build(from: snapshot, userInstruction: instruction)
        let client = di.makeLLMClient()

        di.overlayViewModel.beginAnswer()
        let started = Date()
        var gotFirst = false

        do {
            for try await chunk in client.stream(request) {
                if !gotFirst {
                    gotFirst = true
                    let ms = Date().timeIntervalSince(started) * 1000
                    Log.llm.debug("time-to-first-chunk \(ms, format: .fixed(precision: 0))ms")
                }
                di.overlayViewModel.appendDelta(chunk.delta)
            }
            di.overlayViewModel.finishAnswer()
        } catch let error as LLMError {
            handle(error)
        } catch {
            di.overlayViewModel.showError("Не удалось получить ответ")
        }
    }

    private func handle(_ error: LLMError) {
        switch error {
        case .unauthorized:
            // ключ не показываем, ведём в настройки
            di.overlayViewModel.showError("Проверьте API-ключ в настройках")
        case .badResponse(let code):
            di.overlayViewModel.showError("Ошибка LLM (\(code))")
        default:
            di.overlayViewModel.showError("Сбой соединения с LLM")
        }
    }

    private func regionAroundCursor() -> CGRect? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { return nil }
        // NSEvent — снизу-вверх, CG — сверху-вниз, переворачиваем Y
        let flippedY = screen.frame.height - mouse.y
        let size = CGSize(width: 600, height: 300)
        return CGRect(x: mouse.x - size.width / 2,
                      y: flippedY - size.height / 2,
                      width: size.width, height: size.height)
    }
}
