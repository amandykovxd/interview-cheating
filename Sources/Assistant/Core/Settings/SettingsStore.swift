import Foundation

/// Несекретные настройки. Всё локально, через UserDefaults.
/// Ключей провайдера здесь нет — они только в SecureStore.
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Провайдер

    var provider: LLMProvider {
        get {
            LLMProvider(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .localLlama
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.provider) }
    }

    // Порт локального сервера. Именно его "ждём" при старте.
    var localLlamaPort: Int {
        get {
            let v = defaults.integer(forKey: Keys.localPort)
            return v == 0 ? 11434 : v
        }
        set { defaults.set(newValue, forKey: Keys.localPort) }
    }

    var localLlamaModel: String {
        get { defaults.string(forKey: Keys.localModel) ?? "llama3.1" }
        set { defaults.set(newValue, forKey: Keys.localModel) }
    }

    var openAIModel: String {
        get { defaults.string(forKey: Keys.openAIModel) ?? "gpt-4o-mini" }
        set { defaults.set(newValue, forKey: Keys.openAIModel) }
    }

    // MARK: - Производные значения для LLMClient

    var llmBaseURL: String {
        switch provider {
        case .localLlama: return "http://127.0.0.1:\(localLlamaPort)/v1"
        case .openAI: return "https://api.openai.com/v1"
        }
    }

    var llmModel: String {
        switch provider {
        case .localLlama: return localLlamaModel
        case .openAI: return openAIModel
        }
    }

    var llmRequiresKey: Bool { provider.requiresKey }

    // MARK: - Прочее

    var asrModelName: String {
        get { defaults.string(forKey: Keys.asrModelName) ?? "base" }
        set { defaults.set(newValue, forKey: Keys.asrModelName) }
    }

    // По умолчанию скрываем окно из захвата экрана (см. оговорку в OverlayWindow).
    var hideOverlayFromCapture: Bool {
        get { defaults.object(forKey: Keys.hideOverlayFromCapture) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.hideOverlayFromCapture) }
    }

    // Эхоподавление на микрофоне (Voice Processing). По умолчанию включено.
    var echoCancellation: Bool {
        get { defaults.object(forKey: Keys.echoCancellation) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.echoCancellation) }
    }

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Keys.hasOnboarded) }
        set { defaults.set(newValue, forKey: Keys.hasOnboarded) }
    }

    // Core ML энкодер whisper (ускоряет на ANE). По умолчанию включено —
    // при неудаче загрузки тихо откатываемся на Metal.
    var useCoreML: Bool {
        get { defaults.object(forKey: Keys.useCoreML) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.useCoreML) }
    }

    private enum Keys {
        static let provider = "llm.provider"
        static let localPort = "llm.local.port"
        static let localModel = "llm.local.model"
        static let openAIModel = "llm.openai.model"
        static let asrModelName = "asr.modelName"
        static let hideOverlayFromCapture = "overlay.hideFromCapture"
        static let echoCancellation = "audio.echoCancellation"
        static let hasOnboarded = "app.hasOnboarded"
        static let useCoreML = "asr.useCoreML"
    }
}
