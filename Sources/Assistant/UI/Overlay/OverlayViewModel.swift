import Foundation
import SwiftUI

/// Состояние overlay. Только отображение и ввод, никакой бизнес-логики.
/// Обновляется координатором на main.
@MainActor
final class OverlayViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case listening
        case thinking
        case answering
        case error(String)
    }

    @Published var status: Status = .idle
    @Published var answer: String = ""
    @Published var lastTranscript: String = ""
    @Published var transcript: String = ""      // живой разговор: кто что сказал
    @Published var isListening: Bool = false

    // Состояние LLM-endpoint (ожидание llama на порту / готовность / нет ключа).
    @Published var llmReady: Bool = false
    @Published var llmStatusText: String = ""
    @Published var providerTitle: String = ""
    @Published var isGenerating: Bool = false
    @Published var asrStatusText: String = "ASR: не готов"

    // Панель подключения провайдера.
    @Published var showSettings: Bool = false
    @Published var portText: String = "11434"
    @Published var apiKeyInput: String = ""

    // Текстовый чат с LLM.
    @Published var chatInput: String = ""

    // Действия наружу.
    var onToggleListening: (() -> Void)?
    var onCaptureAndAsk: (() -> Void)?
    var onHideOverlay: (() -> Void)?
    var onUseLocalLlama: ((_ port: Int) -> Void)?
    var onConnectOpenAI: ((_ apiKey: String) -> Void)?
    var onOpenOpenAIKeysPage: (() -> Void)?
    var onToggleSettings: (() -> Void)?
    var onSendMessage: ((_ text: String) -> Void)?
    var onRequestActivation: (() -> Void)?   // активировать приложение при фокусе поля
    var onStopGeneration: (() -> Void)?
    var onAnswerFromConversation: (() -> Void)?   // ответить по услышанному разговору
    var onClearContext: (() -> Void)?

    // Батчим обновление ответа, чтобы не перерисовывать на каждый токен.
    private var pendingAnswer: String = ""
    private var flushTask: Task<Void, Never>?

    func beginAnswer() {
        answer = ""
        pendingAnswer = ""
        status = .answering
        isGenerating = true
    }

    func appendDelta(_ delta: String) {
        pendingAnswer += delta
        scheduleFlush()
    }

    func finishAnswer() {
        flushTask?.cancel()
        flushTask = nil
        answer = pendingAnswer
        isGenerating = false
        status = isListening ? .listening : .idle
    }

    func showError(_ message: String) {
        isGenerating = false
        status = .error(message)
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self else { return }
            self.answer = self.pendingAnswer
            self.flushTask = nil
        }
    }
}
