import Foundation

/// Разбор строк SSE-потока OpenAI-совместимого chat completions.
/// Вынесен отдельно, чтобы гонять на записанных ответах без сети.
enum SSEParser {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }

    /// Возвращает дельту из одной SSE-строки, nil — если строка служебная/пустая/[DONE].
    static func parse(line: String) -> LLMChunk? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty || payload == "[DONE]" { return nil }

        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
              let delta = chunk.choices.first?.delta.content,
              !delta.isEmpty else {
            return nil
        }
        return LLMChunk(delta: delta)
    }
}
