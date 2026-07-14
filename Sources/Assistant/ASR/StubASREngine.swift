import Foundation

/// Заглушка ASR. Нужна, чтобы пайплайн работал end-to-end без модели
/// и как fallback, если whisper недоступен. Реального распознавания не делает.
final class StubASREngine: ASREngine {
    var isAvailable: Bool { true }

    func transcribe(_ segment: AudioSegment) -> AsyncStream<ASRResult> {
        let duration = segment.end - segment.start
        return AsyncStream { continuation in
            // отдаём маркер вместо текста — видно, что сегмент дошёл, но модели нет
            let text = String(format: "[речь %.1fс, ASR-модель не подключена]", duration)
            continuation.yield(ASRResult(text: text, isFinal: true, confidence: 0.0))
            continuation.finish()
        }
    }
}
