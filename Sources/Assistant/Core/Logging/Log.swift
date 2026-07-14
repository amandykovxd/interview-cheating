import Foundation
import OSLog

/// Категории логов по модулям. Секреты и приватный контент сюда не пишем.
enum Log {
    private static let subsystem = "com.assistant.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let asr = Logger(subsystem: subsystem, category: "asr")
    static let vision = Logger(subsystem: subsystem, category: "vision")
    static let llm = Logger(subsystem: subsystem, category: "llm")
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Замер длительности блока — для метрик latency.
    @discardableResult
    static func measure<T>(_ label: String, _ logger: Logger, _ body: () throws -> T) rethrows -> T {
        let start = DispatchTime.now()
        let result = try body()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        logger.debug("\(label, privacy: .public) took \(ms, format: .fixed(precision: 1))ms")
        return result
    }
}
