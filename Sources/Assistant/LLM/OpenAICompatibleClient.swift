import Foundation

/// Клиент к любому OpenAI-совместимому /chat/completions endpoint.
/// По умолчанию — локальный сервер (llama.cpp/Ollama), но так же работает с облаком.
/// Ключ (если endpoint его требует) достаётся из SecureStore прямо перед запросом
/// и в LLMRequest/логи/UI не попадает.
final class OpenAICompatibleClient: LLMClient {
    private let baseURL: URL
    private let model: String
    private let requiresKey: Bool
    private let secureStore: SecureStore
    private let session: URLSession

    init(
        baseURL: URL,
        model: String,
        requiresKey: Bool,
        secureStore: SecureStore,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.model = model
        self.requiresKey = requiresKey
        self.secureStore = secureStore
        self.session = session
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try self.buildRequest(request)
                    let (bytes, response) = try await self.session.bytes(for: urlRequest)
                    try self.validate(response)

                    for try await line in bytes.lines {
                        if let chunk = SSEParser.parse(line: line) {
                            continuation.yield(chunk)   // дельту сразу наверх
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildRequest(_ request: LLMRequest) throws -> URLRequest {
        var url = baseURL
        url.appendPathComponent("chat/completions")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        // ключ подставляем в заголовок здесь и нигде не сохраняем
        if requiresKey {
            guard let key = try secureStore.secret(for: .llmAPIKey), !key.isEmpty else {
                throw LLMError.unauthorized
            }
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "temperature": request.temperature,
            "max_tokens": request.maxTokens,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401, 403: throw LLMError.unauthorized
        default: throw LLMError.badResponse(http.statusCode)
        }
    }
}
