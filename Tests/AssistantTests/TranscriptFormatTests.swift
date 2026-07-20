import XCTest
@testable import Assistant

final class TranscriptFormatTests: XCTestCase {
    func testCollapsesSameSpeaker() {
        let segments = [
            seg(.system, "привет"),
            seg(.system, "как дела"),
            seg(.microphone, "нормально")
        ]
        let text = AppCoordinator.formatTranscript(segments, maxLines: 12)
        XCTAssertEqual(text, "Собеседник: привет как дела\nЯ: нормально")
    }

    func testKeepsLastLinesOnly() {
        let segments = (0..<20).map { seg($0 % 2 == 0 ? .system : .microphone, "реплика\($0)") }
        let text = AppCoordinator.formatTranscript(segments, maxLines: 5)
        XCTAssertEqual(text.split(separator: "\n").count, 5)
        XCTAssertTrue(text.contains("реплика19"))
        XCTAssertFalse(text.contains("реплика0"))
    }

    func testSkipsEmpty() {
        let segments = [seg(.system, "  "), seg(.microphone, "текст")]
        let text = AppCoordinator.formatTranscript(segments, maxLines: 12)
        XCTAssertEqual(text, "Я: текст")
    }

    private func seg(_ source: TranscriptSegment.Source, _ text: String) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, start: 0, end: 1, isFinal: true)
    }
}
