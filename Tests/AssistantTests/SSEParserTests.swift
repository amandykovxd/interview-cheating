import XCTest
@testable import Assistant

final class SSEParserTests: XCTestCase {
    func testParsesDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"при"}}]}"#
        XCTAssertEqual(SSEParser.parse(line: line)?.delta, "при")
    }

    func testIgnoresDone() {
        XCTAssertNil(SSEParser.parse(line: "data: [DONE]"))
    }

    func testIgnoresNonData() {
        XCTAssertNil(SSEParser.parse(line: ": keep-alive"))
        XCTAssertNil(SSEParser.parse(line: ""))
    }

    func testIgnoresEmptyContentDelta() {
        // роль без контента (первый чанк) не даёт дельты
        let line = #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#
        XCTAssertNil(SSEParser.parse(line: line))
    }

    func testFullStreamReconstruction() {
        let lines = [
            #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"при"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"вет"}}]}"#,
            "data: [DONE]"
        ]
        let text = lines.compactMap { SSEParser.parse(line: $0)?.delta }.joined()
        XCTAssertEqual(text, "привет")
    }
}
