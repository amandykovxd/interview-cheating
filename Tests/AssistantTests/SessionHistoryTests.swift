import CryptoKit
import XCTest
@testable import Assistant

final class SessionHistoryTests: XCTestCase {
    func testCryptoRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let crypto = HistoryCrypto(key: key)
        let data = "секрет разговора".data(using: .utf8)!
        let sealed = try crypto.encrypt(data)
        XCTAssertNotEqual(sealed, data)                 // на диске не открытый текст
        XCTAssertEqual(try crypto.decrypt(sealed), data)
    }

    func testDecryptFailsWithWrongKey() throws {
        let sealed = try HistoryCrypto(key: SymmetricKey(size: .bits256))
            .encrypt(Data("x".utf8))
        XCTAssertThrowsError(try HistoryCrypto(key: SymmetricKey(size: .bits256)).decrypt(sealed))
    }

    func testSaveAndLoadRoundTrip() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir, crypto: HistoryCrypto(key: SymmetricKey(size: .bits256)))

        var s = SavedSession(id: UUID(), startedAt: Date())
        s.lines = [.init(speaker: "Собеседник", text: "как устроен деплой")]
        s.exchanges = [.init(question: "деплой?", answer: "через CI", at: Date())]
        try await store.save(s)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.lines.first?.text, "как устроен деплой")
        XCTAssertEqual(loaded.first?.exchanges.first?.answer, "через CI")
    }

    func testDeleteAll() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir, crypto: HistoryCrypto(key: SymmetricKey(size: .bits256)))
        try await store.save(SavedSession(id: UUID(), startedAt: Date()))
        try await store.deleteAll()
        let loaded = try await store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("hist-\(UUID())")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}
