import Foundation

/// Собирает компактный промпт из снимка контекста.
/// Держит бюджет по длине, схлопывает подряд идущие реплики одного источника.
struct PromptBuilder {
    /// Грубый бюджет входа в символах (примерная прокси токенов, ~4 символа/токен).
    var maxInputChars: Int = 6000

    private let system = """
    Ты ассистент. Отвечай кратко и по делу, на языке собеседника. \
    Не повторяй вопрос, не лей воду. Если данных мало — скажи прямо.
    """

    func build(from snapshot: ContextSnapshot, userInstruction: String?) -> LLMRequest {
        var parts: [String] = []

        if let ocr = snapshot.ocr, !ocr.joinedText.isEmpty {
            parts.append("Текст с экрана:\n\(ocr.joinedText)")
        }

        let dialog = collapse(snapshot.segments)
        if !dialog.isEmpty {
            parts.append("Разговор:\n\(dialog)")
        }

        if let instruction = userInstruction, !instruction.isEmpty {
            parts.append("Задача: \(instruction)")
        }

        var content = parts.joined(separator: "\n\n")
        content = trimToBudget(content)

        return LLMRequest(
            messages: [
                LLMMessage(role: .system, content: system),
                LLMMessage(role: .user, content: content)
            ],
            model: "",          // подставит LLMClient из настроек
            maxTokens: 512,
            temperature: 0.3
        )
    }

    /// Схлопываем подряд идущие реплики одного источника в одну строку.
    private func collapse(_ segments: [TranscriptSegment]) -> String {
        var lines: [String] = []
        for seg in segments {
            let speaker = seg.source == .microphone ? "Я" : "Собеседник"
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if let last = lines.last, last.hasPrefix(speaker + ":") {
                lines[lines.count - 1] = last + " " + text
            } else {
                lines.append("\(speaker): \(text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Если вылезли за бюджет — режем самое старое (начало), хвост важнее.
    private func trimToBudget(_ text: String) -> String {
        guard text.count > maxInputChars else { return text }
        let overflow = text.count - maxInputChars
        let start = text.index(text.startIndex, offsetBy: overflow)
        return "…" + String(text[start...])
    }
}
