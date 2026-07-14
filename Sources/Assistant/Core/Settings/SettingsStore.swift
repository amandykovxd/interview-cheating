import Foundation

/// Несекретные настройки. Всё локально, через UserDefaults.
/// Ключей провайдера здесь нет — они только в SecureStore.
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // Базовый URL LLM. По умолчанию — локальный OpenAI-совместимый сервер (llama.cpp/Ollama).
    var llmBaseURL: String {
        get { defaults.string(forKey: Keys.llmBaseURL) ?? "http://127.0.0.1:11434/v1" }
        set { defaults.set(newValue, forKey: Keys.llmBaseURL) }
    }

    var llmModel: String {
        get { defaults.string(forKey: Keys.llmModel) ?? "llama3.1" }
        set { defaults.set(newValue, forKey: Keys.llmModel) }
    }

    // Требует ли выбранный endpoint ключ. Локальный сервер обычно нет.
    var llmRequiresKey: Bool {
        get { defaults.bool(forKey: Keys.llmRequiresKey) }
        set { defaults.set(newValue, forKey: Keys.llmRequiresKey) }
    }

    var asrModelName: String {
        get { defaults.string(forKey: Keys.asrModelName) ?? "base" }
        set { defaults.set(newValue, forKey: Keys.asrModelName) }
    }

    // Экспериментальное скрытие overlay от записи экрана. По умолчанию выключено.
    var hideOverlayFromCapture: Bool {
        get { defaults.bool(forKey: Keys.hideOverlayFromCapture) }
        set { defaults.set(newValue, forKey: Keys.hideOverlayFromCapture) }
    }

    private enum Keys {
        static let llmBaseURL = "llm.baseURL"
        static let llmModel = "llm.model"
        static let llmRequiresKey = "llm.requiresKey"
        static let asrModelName = "asr.modelName"
        static let hideOverlayFromCapture = "overlay.hideFromCapture"
    }
}
