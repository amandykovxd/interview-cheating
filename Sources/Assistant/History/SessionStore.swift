import Foundation

/// Одна сохранённая сессия: разговор + пары вопрос/ответ.
struct SavedSession: Codable, Equatable, Identifiable {
    struct Line: Codable, Equatable {
        let speaker: String
        let text: String
    }
    struct Exchange: Codable, Equatable {
        let question: String
        let answer: String
        let at: Date
    }

    let id: UUID
    let startedAt: Date
    var lines: [Line] = []
    var exchanges: [Exchange] = []

    var isEmpty: Bool { lines.isEmpty && exchanges.isEmpty }
}

/// Хранилище истории на диске, зашифрованное. Пишет только по явному вызову
/// (согласие проверяет вызывающий). Каждая сессия — отдельный .enc файл.
actor SessionStore {
    private let directory: URL
    private let crypto: HistoryCrypto
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL, crypto: HistoryCrypto) {
        self.directory = directory
        self.crypto = crypto
    }

    func save(_ session: SavedSession) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plain = try encoder.encode(session)
        let sealed = try crypto.encrypt(plain)
        try sealed.write(to: fileURL(session.id), options: .atomic)
    }

    func loadAll() throws -> [SavedSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        var result: [SavedSession] = []
        for file in files where file.pathExtension == "enc" {
            guard let data = try? Data(contentsOf: file),
                  let plain = try? crypto.decrypt(data),
                  let session = try? decoder.decode(SavedSession.self, from: plain) else {
                continue   // битый/чужой файл не роняет всю загрузку
            }
            result.append(session)
        }
        return result.sorted { $0.startedAt > $1.startedAt }
    }

    func deleteAll() throws {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "enc" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).enc")
    }
}
