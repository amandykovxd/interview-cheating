import XCTest
@testable import Assistant

final class PromptBuilderTests: XCTestCase {
    func testCollapsesSameSpeaker() {
        let snapshot = ContextSnapshot(
            segments: [
                TranscriptSegment(source: .microphone, text: "привет", start: 0, end: 1, isFinal: true),
                TranscriptSegment(source: .microphone, text: "как дела", start: 1, end: 2, isFinal: true)
            ],
            ocr: nil
        )
        let req = PromptBuilder().build(from: snapshot, userInstruction: nil)
        let user = req.messages.last!.content
        XCTAssertTrue(user.contains("Я: привет как дела"))
    }

    func testIncludesOCRAndInstruction() {
        let snapshot = ContextSnapshot(
            segments: [],
            ocr: OCRResult(lines: [.init(text: "error 42", confidence: 0.9)], capturedAt: Date())
        )
        let req = PromptBuilder().build(from: snapshot, userInstruction: "объясни ошибку")
        let user = req.messages.last!.content
        XCTAssertTrue(user.contains("error 42"))
        XCTAssertTrue(user.contains("объясни ошибку"))
    }

    func testBudgetTrimsFromStart() {
        var builder = PromptBuilder()
        builder.maxInputChars = 50
        let long = String(repeating: "a", count: 200)
        let snapshot = ContextSnapshot(
            segments: [TranscriptSegment(source: .system, text: long, start: 0, end: 1, isFinal: true)],
            ocr: nil
        )
        let req = builder.build(from: snapshot, userInstruction: nil)
        let user = req.messages.last!.content
        XCTAssertLessThanOrEqual(user.count, 51) // 50 + маркер "…"
        XCTAssertTrue(user.hasPrefix("…"))
    }

    func testSystemPromptPresent() {
        let req = PromptBuilder().build(from: ContextSnapshot(segments: [], ocr: nil),
                                        userInstruction: nil)
        XCTAssertEqual(req.messages.first?.role, .system)
    }
}
