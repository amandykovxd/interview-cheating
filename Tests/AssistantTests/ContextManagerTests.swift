import XCTest
@testable import Assistant

final class ContextManagerTests: XCTestCase {
    func testPartialShowsInDisplayButNotInPrompt() async {
        let manager = ContextManager()

        // идёт речь: сначала partial, потом финал
        await manager.ingest(part(.system, "как настроить", final: false))
        var display = await manager.displaySegments()
        var snapshot = await manager.snapshot()

        // partial виден в живом транскрипте
        XCTAssertEqual(display.map(\.text), ["как настроить"])
        // но в промпт LLM не уходит
        XCTAssertTrue(snapshot.segments.isEmpty)

        await manager.ingest(part(.system, "как настроить деплой", final: true))
        display = await manager.displaySegments()
        snapshot = await manager.snapshot()

        XCTAssertEqual(display.map(\.text), ["как настроить деплой"])
        XCTAssertEqual(snapshot.segments.map(\.text), ["как настроить деплой"])
    }

    func testResetClears() async {
        let manager = ContextManager()
        await manager.ingest(part(.microphone, "тест", final: true))
        await manager.reset()
        let display = await manager.displaySegments()
        XCTAssertTrue(display.isEmpty)
    }

    private func part(_ source: TranscriptSegment.Source, _ text: String, final: Bool) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, start: 0, end: 1, isFinal: final)
    }
}
