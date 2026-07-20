import CryptoKit
import Foundation

/// Ручная сборка зависимостей. DI-фреймворк на такой объём не нужен.
@MainActor
final class DIContainer {
    let settings = SettingsStore()
    let secureStore: SecureStore = KeychainSecureStore()

    let permissions = PermissionsService()
    lazy var onboarding = OnboardingWindowController(permissions: permissions)

    // История: ключ шифрования в Keychain, файлы в Application Support.
    lazy var sessionStore: SessionStore = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Assistant/History", isDirectory: true)
        let crypto = (try? HistoryCrypto.withKeychainKey(secureStore))
            ?? HistoryCrypto(key: .init(size: .bits256))
        return SessionStore(directory: dir, crypto: crypto)
    }()

    lazy var contextManager = ContextManager()
    lazy var promptBuilder = PromptBuilder()
    lazy var visionPipeline = VisionPipeline()
    lazy var regionSelector = RegionSelector()
    lazy var hotkeys = HotkeyService()
    lazy var overlayViewModel = OverlayViewModel()

    // Стартует на заглушке, координатор подменит на whisper, когда модель готова.
    lazy var asrEngine = ASREngineHolder()
    lazy var modelStore = WhisperModelStore()

    lazy var audioPipeline = AudioPipeline(
        source: MicrophoneSource(echoCancellation: settings.echoCancellation))
    // системный звук отдельным пайплайном: собеседник в созвоне звучит здесь
    lazy var systemAudioPipeline = AudioPipeline(source: SystemAudioSource())

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
