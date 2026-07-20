import Foundation

/// Сегмент аудио, готовый к распознаванию: 16 kHz, mono, float32.
struct AudioSegment {
    let samples: [Float]
    let sampleRate: Double
    let source: TranscriptSegment.Source
    let start: TimeInterval
    let end: TimeInterval
    /// true — промежуточный кусок ещё идущей речи (для потокового вывода),
    /// false — финал по паузе VAD.
    var isPartial: Bool = false
}

struct ASRResult {
    let text: String
    let isFinal: Bool
    let confidence: Float
}

/// Движок распознавания. За этим протоколом прячется whisper.cpp / стаб / что угодно.
protocol ASREngine {
    /// Готов ли движок (модель загружена). Если нет — координатор работает без ASR.
    var isAvailable: Bool { get }

    /// Распознать сегмент. Может отдавать несколько частичных результатов и один финальный.
    func transcribe(_ segment: AudioSegment) -> AsyncStream<ASRResult>
}
