import Foundation

/// Проверяет, поднят ли LLM endpoint. Для локальной llama это ответ на порту,
/// для OpenAI — что ключ есть и /models отдаёт 200.
struct LLMHealthChecker {
    private let session: URLSession

    init(session: URLSession = .shared) {
        // короткие таймауты: проверка не должна залипать
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        self.session = URLSession(configuration: config)
    }

    enum Health: Equatable {
        case ready
        case waiting          // сервер не отвечает (llama ещё не поднята)
        case needsKey         // провайдер требует ключ, а его нет
        case unauthorized     // ключ есть, но отвергнут
    }

    func check(baseURL: URL, requiresKey: Bool, secureStore: SecureStore) async -> Health {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"

        if requiresKey {
            guard let key = try? secureStore.secret(for: .llmAPIKey), !key.isEmpty else {
                return .needsKey
            }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .waiting }
            switch http.statusCode {
            case 200...299: return .ready
            case 401, 403: return .unauthorized
            default: return .waiting
            }
        } catch {
            return .waiting
        }
    }
}
