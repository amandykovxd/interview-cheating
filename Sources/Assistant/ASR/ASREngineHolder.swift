import Foundation

/// Подменяемый ASR. Стартуем на заглушке, а когда модель скачана и загружена —
/// переключаемся на whisper. Координатор об этом не знает: для него это один
/// ASREngine за протоколом.
final class ASREngineHolder: ASREngine {
    private let lock = NSLock()
    private var current: ASREngine

    init(initial: ASREngine = StubASREngine()) {
        current = initial
    }

    private var engine: ASREngine {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func replace(with engine: ASREngine) {
        lock.lock()
        current = engine
        lock.unlock()
    }

    var isAvailable: Bool { engine.isAvailable }

    func transcribe(_ segment: AudioSegment) -> AsyncStream<ASRResult> {
        engine.transcribe(segment)
    }
}
