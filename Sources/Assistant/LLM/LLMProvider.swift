import Foundation

/// Провайдер LLM. Приложение — оболочка: своего аккаунта нет, пользователь
/// подключает либо локальный сервер, либо свой OpenAI-ключ.
enum LLMProvider: String, CaseIterable {
    case localLlama   // локальный OpenAI-совместимый сервер (Ollama / llama.cpp)
    case openAI       // облако OpenAI по API-ключу пользователя

    var title: String {
        switch self {
        case .localLlama: return "Локальная llama"
        case .openAI: return "ChatGPT (OpenAI API)"
        }
    }

    var requiresKey: Bool {
        switch self {
        case .localLlama: return false
        case .openAI: return true
        }
    }

    /// Куда вести пользователя за ключом. Важно: это API-ключ платформы OpenAI,
    /// а не вход в подписку ChatGPT — подписка API-доступа не даёт.
    var accountURL: URL? {
        switch self {
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .localLlama: return nil
        }
    }
}
