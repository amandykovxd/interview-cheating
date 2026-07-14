import Foundation

/// Одна реплика транскрипта с таймстампами относительно старта сессии.
struct TranscriptSegment: Equatable, Identifiable {
    enum Source: Equatable {
        case system      // системный звук (собеседник)
        case microphone  // пользователь
    }

    let id: UUID
    let source: Source
    var text: String
    let start: TimeInterval
    var end: TimeInterval
    var isFinal: Bool
    var confidence: Float

    init(
        id: UUID = UUID(),
        source: Source,
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        isFinal: Bool,
        confidence: Float = 1.0
    ) {
        self.id = id
        self.source = source
        self.text = text
        self.start = start
        self.end = end
        self.isFinal = isFinal
        self.confidence = confidence
    }
}

/// Результат OCR. Держим строки с координатами — пригодится для выборки области.
struct OCRResult: Equatable {
    struct Line: Equatable {
        let text: String
        let confidence: Float
    }

    let lines: [Line]
    let capturedAt: Date

    var joinedText: String {
        lines.map(\.text).joined(separator: "\n")
    }
}
