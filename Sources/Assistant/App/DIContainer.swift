import Foundation

/// Ручная сборка зависимостей. DI-фреймворк на такой объём не нужен.
@MainActor
final class DIContainer {
    let settings = SettingsStore()
    let secureStore: SecureStore = KeychainSecureStore()

    lazy var contextManager = ContextManager()
    lazy var promptBuilder = PromptBuilder()
    lazy var visionPipeline = VisionPipeline()
    lazy var hotkeys = HotkeyService()
    lazy var overlayViewModel = OverlayViewModel()

    lazy var asrEngine: ASREngine = ASREngineFactory.make(modelName: settings.asrModelName)

    lazy var audioPipeline = AudioPipeline(source: MicrophoneSource())

    func makeLLMClient() -> LLMClient {
        let url = URL(string: settings.llmBaseURL) ?? URL(string: "http://127.0.0.1:11434/v1")!
        return OpenAICompatibleClient(
            baseURL: url,
            model: settings.llmModel,
            requiresKey: settings.llmRequiresKey,
            secureStore: secureStore
        )
    }
}
