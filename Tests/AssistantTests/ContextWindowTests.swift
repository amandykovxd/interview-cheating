import XCTest
@testable import Assistant

final class ContextWindowTests: XCTestCase {
    func testStripOverlapRemovesRepeatedTail() {
        let result = ContextWindow.stripOverlap(previous: "привет как дела",
                                                current: "как дела у тебя")
        XCTAssertEqual(result, "у тебя")
    }

    func testStripOverlapNoCommonPart() {
        let result = ContextWindow.stripOverlap(previous: "раз два", current: "три четыре")
        XCTAssertEqual(result, "три четыре")
    }

    func testLowConfidenceFinalIsDropped() {
        var window = ContextWindow()
        window.minConfidence = 0.5
        window.addOrUpdate(seg(text: "мусор", final: true, conf: 0.1))
        XCTAssertTrue(window.segments.isEmpty)
    }

    func testPartialIsReplacedThenFinalized() {
        var window = ContextWindow()
        window.addOrUpdate(seg(text: "прив", final: false, conf: 0.9))
        window.addOrUpdate(seg(text: "привет", final: false, conf: 0.9))
        XCTAssertEqual(window.segments.count, 1)
        XCTAssertEqual(window.segments.first?.text, "привет")

        window.addOrUpdate(seg(text: "привет мир", final: true, conf: 0.9))
        XCTAssertEqual(window.segments.count, 1)
        XCTAssertTrue(window.segments.first!.isFinal)
    }

    func testOldSegmentsTrimmed() {
        var window = ContextWindow()
        window.maxDuration = 10
        window.addOrUpdate(TranscriptSegment(source: .system, text: "старое",
                                             start: 0, end: 1, isFinal: true))
        window.addOrUpdate(TranscriptSegment(source: .system, text: "новое",
                                             start: 100, end: 101, isFinal: true))
        XCTAssertEqual(window.segments.map(\.text), ["новое"])
    }

    private func seg(text: String, final: Bool, conf: Float) -> TranscriptSegment {
        TranscriptSegment(source: .microphone, text: text, start: 0, end: 1,
                          isFinal: final, confidence: conf)
    }
}
