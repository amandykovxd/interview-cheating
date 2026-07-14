import Foundation

/// Скользящее окно контекста в памяти. Никакой БД, ничего на диск.
/// Держит последние реплики и свежий OCR, режет старое по времени.
struct ContextWindow {
    private(set) var segments: [TranscriptSegment] = []
    private(set) var lastOCR: OCRResult?

    /// Сколько секунд транскрипта держим.
    var maxDuration: TimeInterval = 120
    /// Порог уверенности — ниже него финальные сегменты не копим.
    var minConfidence: Float = 0.3

    mutating func addOrUpdate(_ segment: TranscriptSegment) {
        // отбрасываем совсем неуверенный мусор
        if segment.isFinal && segment.confidence < minConfidence { return }

        // частичный результат обновляет последний нефинальный того же источника
        if !segment.isFinal,
           let idx = lastPartialIndex(for: segment.source) {
            segments[idx] = segment
            return
        }

        // финализация ранее висевшего частичного
        if segment.isFinal,
           let idx = lastPartialIndex(for: segment.source) {
            segments[idx] = deduplicated(segment, against: idx)
            trim(now: segment.end)
            return
        }

        segments.append(deduplicated(segment, against: nil))
        trim(now: segment.end)
    }

    mutating func setOCR(_ result: OCRResult) {
        lastOCR = result
    }

    mutating func reset() {
        segments.removeAll()
        lastOCR = nil
    }

    private func lastPartialIndex(for source: TranscriptSegment.Source) -> Int? {
        segments.lastIndex { $0.source == source && !$0.isFinal }
    }

    /// Срезаем перекрытие хвоста предыдущего сегмента с началом нового —
    /// потоковый ASR часто повторяет края окон.
    private func deduplicated(_ segment: TranscriptSegment, against index: Int?) -> TranscriptSegment {
        guard let prev = previousFinal(before: index) else { return segment }
        var result = segment
        result.text = Self.stripOverlap(previous: prev.text, current: segment.text)
        return result
    }

    private func previousFinal(before index: Int?) -> TranscriptSegment? {
        let upper = index ?? segments.count
        for i in stride(from: upper - 1, through: 0, by: -1) where segments[i].isFinal {
            return segments[i]
        }
        return nil
    }

    private mutating func trim(now: TimeInterval) {
        let cutoff = now - maxDuration
        segments.removeAll { $0.isFinal && $0.end < cutoff }
    }

    /// Убирает из начала current самый длинный суффикс previous, который с ним совпадает.
    static func stripOverlap(previous: String, current: String) -> String {
        let prev = previous.lowercased()
        let curr = current.lowercased()
        let maxLen = min(prev.count, curr.count)
        var overlap = 0
        for len in stride(from: maxLen, through: 1, by: -1) {
            let prevSuffix = prev.suffix(len)
            let currPrefix = curr.prefix(len)
            if prevSuffix == currPrefix {
                overlap = len
                break
            }
        }
        if overlap == 0 { return current }
        let idx = current.index(current.startIndex, offsetBy: overlap)
        return String(current[idx...]).trimmingCharacters(in: .whitespaces)
    }
}
