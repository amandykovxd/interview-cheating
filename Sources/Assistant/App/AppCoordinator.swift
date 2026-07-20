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
    private var systemAudioTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?
    private var llmMonitorTask: Task<Void, Never>?
    private var asrSetupTask: Task<Void, Never>?

    private let health = LLMHealthChecker()

    init(di: DIContainer) {
        self.di = di
        self.overlay = OverlayWindowController(viewModel: di.overlayViewModel)
        self.menuBar = MenuBarController()
    }

    func start() {
        wireMenuBar()
        wireOverlay()
        wireHotkeys()
        di.overlayViewModel.status = .idle
        refreshProviderTitle()
        startLLMMonitor()
        prepareASR()
        overlay.show()
        applyCaptureHiding()
        maybeShowOnboarding()
        Log.app.info("coordinator started")
    }

    private func maybeShowOnboarding() {
        di.onboarding.onClosed = { [weak self] in self?.di.settings.hasOnboarded = true }
        // первый запуск или нет обязательного микрофона — показываем экран доступов
        if !di.settings.hasOnboarded || !di.permissions.essentialGranted {
            di.onboarding.show()
        }
    }

    // MARK: - ASR: модель и подмена движка

    /// Готовим whisper в фоне: качаем модель, если её нет, грузим и подменяем
    /// заглушку. До этого момента приложение работает без ASR, но не падает.
    private func prepareASR() {
        asrSetupTask?.cancel()
        let model = WhisperModel.named(di.settings.asrModelName)
        let store = di.modelStore
        let holder = di.asrEngine
        let vm = di.overlayViewModel
        let wantCoreML = di.settings.useCoreML
        vm.asrModelName = model.name

        asrSetupTask = Task { [weak self] in
            do {
                vm.asrStatusText = "ASR: подготовка модели \(model.name)"
                let url = try await store.ensureAvailable(model) { progress in
                    Task { @MainActor in
                        vm.asrStatusText = "ASR: загрузка \(model.name) \(Int(progress * 100))%"
                    }
                }

                // Core ML энкодер — best-effort: качаем zip, при неудаче просто Metal
                if wantCoreML, !(await store.isEncoderDownloaded(model)) {
                    vm.asrStatusText = "ASR: загрузка Core ML \(model.name)"
                    do {
                        _ = try await store.ensureCoreMLEncoder(model)
                    } catch {
                        Log.asr.error("Core ML энкодер не скачался: \(error.localizedDescription)")
                    }
                }

                // загрузка модели в память — тяжёлая, уводим с main
                let engine = await Task.detached(priority: .userInitiated) {
                    WhisperASREngine(modelPath: url)
                }.value

                guard let engine else {
                    vm.asrStatusText = "ASR: модель не загрузилась"
                    return
                }
                holder.replace(with: engine)
                let backend = engine.usesCoreML ? "Core ML" : "Metal"
                vm.asrStatusText = "ASR: \(model.name) · \(backend)"
                Log.asr.info("ASR переключён на whisper (\(model.name), \(backend))")
            } catch {
                // без ASR продолжаем работать: OCR и текстовый чат остаются
                vm.asrStatusText = "ASR: недоступен"
                Log.asr.error("подготовка ASR не удалась: \(error.localizedDescription)")
                _ = self
            }
        }
    }

    // MARK: - Проводка

    private func wireMenuBar() {
        menuBar.onToggleOverlay = { [weak self] in self?.overlay.toggle() }
        menuBar.onCaptureAndAsk = { [weak self] in self?.captureAndAsk() }
        menuBar.onPermissions = { [weak self] in self?.di.onboarding.show() }
        menuBar.onQuit = { NSApp.terminate(nil) }
    }

    private func wireOverlay() {
        let vm = di.overlayViewModel
        vm.onToggleListening = { [weak self] in self?.toggleAudio() }
        vm.onCaptureAndAsk = { [weak self] in self?.captureAndAsk() }
        vm.onHideOverlay = { [weak self] in self?.overlay.hide() }
        vm.onUseLocalLlama = { [weak self] port in self?.useLocalLlama(port: port) }
        vm.onConnectOpenAI = { [weak self] key in self?.connectOpenAI(apiKey: key) }
        vm.onOpenOpenAIKeysPage = { [weak self] in self?.openOpenAIKeysPage() }
        vm.onToggleSettings = { [weak self] in self?.toggleSettings() }
        vm.onSendMessage = { [weak self] text in self?.sendChat(text) }
        vm.onRequestActivation = { [weak self] in self?.activateForInput() }
        vm.onStopGeneration = { [weak self] in self?.stopGeneration() }
        vm.onAnswerFromConversation = { [weak self] in self?.answerFromConversation() }
        vm.onClearContext = { [weak self] in self?.clearContext() }
        vm.onSelectModel = { [weak self] name in self?.selectModel(name) }
        vm.portText = String(di.settings.localLlamaPort)
        vm.asrModelName = di.settings.asrModelName
    }

    // Смена модели ASR: сохраняем и перезагружаем движок (скачает, если нужно).
    private func selectModel(_ name: String) {
        guard name != di.settings.asrModelName else { return }
        di.settings.asrModelName = name
        prepareASR()
    }

    // Основной cheat-флоу: ответить на то, что собеседник спросил вслух.
    // Без OCR — только по услышанному разговору.
    private func answerFromConversation() {
        answerTask?.cancel()
        overlay.show()
        answerTask = Task { [weak self] in
            await self?.streamAnswer(
                instruction: "Ответь по существу на последний вопрос или реплику собеседника. Коротко, без воды."
            )
        }
    }

    // Сброс всего накопленного: и разговор, и ответ, и OCR.
    private func clearContext() {
        answerTask?.cancel()
        answerTask = nil
        let manager = di.contextManager
        Task { await manager.reset() }
        let vm = di.overlayViewModel
        vm.transcript = ""
        vm.lastTranscript = ""
        vm.answer = ""
        vm.status = vm.isListening ? .listening : .idle
    }

    // Прервать генерацию: отменяем задачу стрима, частичный ответ оставляем на экране.
    private func stopGeneration() {
        answerTask?.cancel()
        answerTask = nil
        di.overlayViewModel.finishAnswer()
    }

    // Активируем приложение и делаем окно key — иначе поля ввода accessory-приложения
    // с nonactivating-панелью не получают клавиатуру (⌘V/набор).
    private func activateForInput() {
        NSApp.activate(ignoringOtherApps: true)
        overlay.window.makeKeyAndOrderFront(nil)
    }

    private func toggleSettings() {
        let vm = di.overlayViewModel
        vm.showSettings.toggle()
        if vm.showSettings {
            activateForInput()
        } else {
            overlay.window.resignKey()
        }
    }

    // Текстовый запрос из поля чата: тот же путь, что и остальные запросы к LLM.
    private func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        answerTask?.cancel()
        answerTask = Task { [weak self] in
            await self?.streamAnswer(instruction: trimmed)
        }
    }

    // MARK: - Провайдер LLM

    private func refreshProviderTitle() {
        di.overlayViewModel.providerTitle = di.settings.provider.title
    }

    private func useLocalLlama(port: Int) {
        di.settings.provider = .localLlama
        di.settings.localLlamaPort = port
        refreshProviderTitle()
        Log.llm.info("switched to local llama on :\(port)")
        startLLMMonitor()
    }

    private func connectOpenAI(apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            // ключ уходит только в Keychain, в логи/UI не пишем
            try di.secureStore.setSecret(trimmed, for: .llmAPIKey)
            di.settings.provider = .openAI
            refreshProviderTitle()
            di.overlayViewModel.showSettings = false
            Log.llm.info("OpenAI key stored, provider switched")
            startLLMMonitor()
        } catch {
            di.overlayViewModel.showError("Не удалось сохранить ключ")
        }
    }

    private func openOpenAIKeysPage() {
        if let url = LLMProvider.openAI.accountURL {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Ожидание LLM endpoint

    private func startLLMMonitor() {
        llmMonitorTask?.cancel()
        let settings = di.settings
        let store = di.secureStore
        llmMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let base = URL(string: settings.llmBaseURL)!
                let result = await self.health.check(
                    baseURL: base,
                    requiresKey: settings.llmRequiresKey,
                    secureStore: store
                )
                self.applyHealth(result)
                // не готово — опрашиваем чаще, готово — реже
                let delay: UInt64 = result == .ready ? 15 : 3
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
    }

    private func applyHealth(_ health: LLMHealthChecker.Health) {
        let vm = di.overlayViewModel
        switch health {
        case .ready:
            vm.llmReady = true
            vm.llmStatusText = "LLM готов"
        case .waiting:
            vm.llmReady = false
            if di.settings.provider == .localLlama {
                vm.llmStatusText = "жду llama на :\(di.settings.localLlamaPort)"
            } else {
                vm.llmStatusText = "нет ответа от OpenAI"
            }
        case .needsKey:
            vm.llmReady = false
            vm.llmStatusText = "нужен ключ OpenAI"
        case .unauthorized:
            vm.llmReady = false
            vm.llmStatusText = "ключ отклонён"
        }
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
        guard audioTask == nil else { return }
        di.overlayViewModel.status = .listening

        // Микрофон (моя речь). Без него слушать нечего — это ошибка.
        do {
            let mic = try di.audioPipeline.start()
            di.overlayViewModel.isListening = true
            audioTask = Task { [weak self] in
                for await segment in mic {
                    await self?.transcribe(segment)
                }
            }
        } catch {
            Log.audio.error("mic start failed: \(error.localizedDescription)")
            di.overlayViewModel.isListening = false
            di.overlayViewModel.showError("Нет доступа к микрофону")
            return
        }

        // Системный звук (собеседник). Может быть недоступен: старая macOS,
        // нет разрешения на запись звука — тогда просто слушаем один микрофон.
        do {
            let system = try di.systemAudioPipeline.start()
            systemAudioTask = Task { [weak self] in
                for await segment in system {
                    await self?.transcribe(segment)
                }
            }
            watchSystemAudio()
        } catch {
            Log.audio.error("system audio unavailable: \(error.localizedDescription)")
            di.overlayViewModel.asrStatusText = "звук собеседника недоступен"
        }
    }

    // tap стартует без ошибки, но без разрешения на запись звука не отдаёт буферы.
    // Если за пару секунд ничего не пришло — подсказываем про разрешение.
    private func watchSystemAudio() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, self.systemAudioTask != nil else { return }
            if !self.di.systemAudioPipeline.didReceiveInput {
                self.di.overlayViewModel.asrStatusText =
                    "звук собеседника: нет сигнала (разрешите запись звука)"
                Log.audio.error("system audio: нет буферов, вероятно нет разрешения")
            }
        }
    }

    private func stopAudio() {
        audioTask?.cancel()
        audioTask = nil
        systemAudioTask?.cancel()
        systemAudioTask = nil
        di.audioPipeline.stop()
        di.systemAudioPipeline.stop()
        di.overlayViewModel.isListening = false
        if case .listening = di.overlayViewModel.status {
            di.overlayViewModel.status = .idle
        }
    }

    private func toggleAudio() {
        if audioTask == nil {
            startAudio()
        } else {
            stopAudio()
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
            // обновляем живой транскрипт и на partial, и на финал
            await refreshTranscript()
        }
    }

    // Живой транскрипт для overlay: финалы + текущие partial-реплики,
    // схлопнутые по говорящему.
    private func refreshTranscript() async {
        let segments = await di.contextManager.displaySegments()
        di.overlayViewModel.transcript = Self.formatTranscript(segments, maxLines: 12)
    }

    nonisolated static func formatTranscript(_ segments: [TranscriptSegment], maxLines: Int) -> String {
        var lines: [String] = []
        for seg in segments {
            let speaker = seg.source == .microphone ? "Я" : "Собеседник"
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if let last = lines.last, last.hasPrefix(speaker + ":") {
                lines[lines.count - 1] = last + " " + text
            } else {
                lines.append("\(speaker): \(text)")
            }
        }
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    // MARK: - Хоткей: OCR + запрос к LLM

    private func captureAndAsk() {
        answerTask?.cancel()
        answerTask = Task { [weak self] in
            guard let self else { return }

            // пользователь выделяет область экрана мышью; Escape — отмена
            guard let rect = await self.selectRegion() else { return }

            self.di.overlayViewModel.status = .thinking
            self.overlay.show()

            if let ocr = await self.di.visionPipeline.recognizeRegion(rect) {
                await self.di.contextManager.ingest(ocr: ocr)
            }
            await self.streamAnswer(instruction: "Помоги с тем, что на экране и в разговоре.")
        }
    }

    private func selectRegion() async -> CGRect? {
        await withCheckedContinuation { cont in
            di.regionSelector.selectRegion { rect in cont.resume(returning: rect) }
        }
    }

    private func streamAnswer(instruction: String) async {
        guard di.overlayViewModel.llmReady else {
            // не готов — не отправляем, показываем что именно ждём
            di.overlayViewModel.showError(di.overlayViewModel.llmStatusText)
            return
        }
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
        } catch is CancellationError {
            // прервали вручную — оставляем частичный ответ, ошибку не показываем
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
}
