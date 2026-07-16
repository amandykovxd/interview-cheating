import Foundation

/// Модели ggml для whisper. В бандл не кладём — качаем при первом запуске
/// в Application Support и переиспользуем.
struct WhisperModel {
    let name: String
    let sizeMB: Int

    /// tiny/base быстрые, но плохо держат термины. small — разумный дефолт
    /// для realtime на Apple Silicon. Всё multilingual, без .en-вариантов:
    /// нужен русский вперемешку с английскими терминами.
    static let tiny = WhisperModel(name: "tiny", sizeMB: 75)
    static let base = WhisperModel(name: "base", sizeMB: 142)
    static let small = WhisperModel(name: "small", sizeMB: 466)

    static let all: [WhisperModel] = [tiny, base, small]

    static func named(_ name: String) -> WhisperModel {
        all.first { $0.name == name } ?? base
    }

    var fileName: String { "ggml-\(name).bin" }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }
}

enum ModelStoreError: Error {
    case badResponse(Int)
    case writeFailed
}

/// Где лежат модели и как их получить.
actor WhisperModelStore {
    enum State: Equatable {
        case missing
        case downloading(progress: Double)
        case ready(URL)
        case failed(String)
    }

    private(set) var state: State = .missing
    private var downloadTask: Task<URL, Error>?

    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        directory = base.appendingPathComponent("Assistant/Models", isDirectory: true)
    }

    func localURL(for model: WhisperModel) -> URL {
        directory.appendingPathComponent(model.fileName)
    }

    func isDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    /// Отдаёт путь к модели, при необходимости скачивая. Повторные вызовы во время
    /// загрузки переиспользуют одну задачу, а не плодят параллельные скачивания.
    func ensureAvailable(_ model: WhisperModel,
                         onProgress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let url = localURL(for: model)
        if FileManager.default.fileExists(atPath: url.path) {
            state = .ready(url)
            return url
        }
        if let task = downloadTask {
            return try await task.value
        }

        let task = Task<URL, Error> {
            try await download(model, to: url, onProgress: onProgress)
        }
        downloadTask = task
        defer { downloadTask = nil }

        do {
            let result = try await task.value
            state = .ready(result)
            return result
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    private func download(_ model: WhisperModel,
                          to destination: URL,
                          onProgress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        state = .downloading(progress: 0)
        Log.asr.info("downloading model \(model.name) (~\(model.sizeMB)MB)")

        let (bytes, response) = try await URLSession.shared.bytes(from: model.downloadURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModelStoreError.badResponse(code)
        }

        let total = http.expectedContentLength
        // пишем во временный файл, чтобы прерванная загрузка не оставила битую модель
        let tmp = destination.appendingPathExtension("part")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tmp) else {
            throw ModelStoreError.writeFailed
        }
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var received: Int64 = 0
        var lastReported = 0.0

        for try await byte in bytes {
            buffer.append(byte)
            received += 1
            if buffer.count >= (1 << 20) {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 {
                    let p = Double(received) / Double(total)
                    if p - lastReported > 0.01 {
                        lastReported = p
                        state = .downloading(progress: p)
                        onProgress(p)
                    }
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        try handle.close()

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
        onProgress(1.0)
        Log.asr.info("model \(model.name) ready")
        return destination
    }
}
