import Foundation
import WhisperCore

/// Перехват логов whisper. У whisper.cpp нет API «загружен ли Core ML»,
/// но он это пишет в лог — ловим и по нему определяем факт загрузки.
enum WhisperLog {
    private static let lock = NSLock()
    private static var lines: [String] = []
    private static var installed = false

    static func installIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        guard !installed else { return }
        installed = true
        // замыкание без захвата -> конвертируется в C-функцию
        whisper_log_set({ _, message, _ in
            guard let message else { return }
            WhisperLog.record(String(cString: message))
        }, nil)
    }

    static func clear() {
        lock.lock(); lines.removeAll(); lock.unlock()
    }

    static func joined() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined()
    }

    private static func record(_ s: String) {
        lock.lock(); lines.append(s); lock.unlock()
    }
}
