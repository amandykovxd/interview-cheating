import Foundation

struct LLMMessage {
    enum Role: String { case system, user, assistant }
    let role: Role
    let content: String
}

struct LLMRequest {
    let messages: [LLMMessage]
    let model: String
    let maxTokens: Int
    let temperature: Double
}

struct LLMChunk {
    let delta: String
}

enum LLMError: Error {
    case unauthorized          // проблема с ключом — ведём в настройки, ключ не показываем
    case badResponse(Int)
    case transport(Error)
    case decoding
}

/// Клиент LLM. Реализации: локальный OpenAI-совместимый сервер или облачный провайдер.
/// Ключ (если нужен) достаётся из SecureStore внутри реализации, наружу не выходит.
protocol LLMClient {
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMChunk, Error>
}
