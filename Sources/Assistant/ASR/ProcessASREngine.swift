import Foundation

/// ASR, изолированный в отдельном процессе (WhisperWorker). Если whisper упадёт,
/// умрёт worker, а не приложение — мы поймаем EOF и перезапустим его.
/// Общается по бинарному протоколу через stdin/stdout worker-а.
final class ProcessASREngine: ASREngine {
    private let workerURL: URL
    private let modelPath: URL
    private let lock = NSLock()          // один запрос за раз
    private var proc: Process?
    private var toWorker: FileHandle?
    private var fromWorker: FileHandle?
    private var busy = false             // для drop-if-busy на partial

    private(set) var usesCoreML = false
    private(set) var didStart = false

    var isAvailable: Bool { didStart }

    // Запись в сломанный pipe (worker умер) иначе шлёт SIGPIPE и роняет нас.
    private static let sigpipeIgnored: Void = { signal(SIGPIPE, SIG_IGN) }()

    init(workerURL: URL, modelPath: URL) {
        _ = Self.sigpipeIgnored
        self.workerURL = workerURL
        self.modelPath = modelPath
    }

    /// Пытается поднять worker и загрузить модель. false — не удалось (нужен fallback).
    @discardableResult
    func start() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return spawnLocked()
    }

    func transcribe(_ segment: AudioSegment) -> AsyncStream<ASRResult> {
        AsyncStream { continuation in
            // partial отбрасываем, если worker занят; финалы ждут
            lock.lock()
            if segment.isPartial && busy {
                lock.unlock(); continuation.finish(); return
            }
            busy = true
            let result = requestLocked(segment.samples)
            busy = false
            lock.unlock()

            if let result, !result.text.isEmpty {
                continuation.yield(ASRResult(text: result.text,
                                             isFinal: !segment.isPartial,
                                             confidence: result.confidence))
            }
            continuation.finish()
        }
    }

    func shutdown() {
        lock.lock(); defer { lock.unlock() }
        if let toWorker {
            var end = UInt32(0xFFFF_FFFF)
            try? toWorker.write(contentsOf: Data(bytes: &end, count: 4))
        }
        proc?.terminate()
        cleanupLocked()
    }

    // MARK: - Внутреннее (под lock)

    private func spawnLocked() -> Bool {
        let p = Process()
        p.executableURL = workerURL
        p.arguments = [modelPath.path]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice   // логи worker не мешают

        do {
            try p.run()
        } catch {
            Log.asr.error("worker не запустился: \(error.localizedDescription)")
            return false
        }
        proc = p
        toWorker = inPipe.fileHandleForWriting
        fromWorker = outPipe.fileHandleForReading

        // handshake: статус загрузки модели
        guard let status = readU32Locked(), status != 0 else {
            Log.asr.error("worker: модель не загрузилась")
            cleanupLocked()
            return false
        }
        let coreml = (status == 3)
        usesCoreML = coreml
        didStart = true
        Log.asr.info("worker поднят (coreml=\(coreml))")
        return true
    }

    private func requestLocked(_ samples: [Float]) -> (text: String, confidence: Float)? {
        guard didStart else { return nil }
        // запрос: nSamples, flags, floats
        var n = UInt32(samples.count)
        var flags = UInt32(0)
        var req = Data()
        req.append(Data(bytes: &n, count: 4))
        req.append(Data(bytes: &flags, count: 4))
        samples.withUnsafeBytes { req.append(contentsOf: $0) }

        do {
            try toWorker?.write(contentsOf: req)
        } catch {
            handleDeathLocked(); return nil
        }

        // ответ: textLen, confidence, utf8
        guard let lenData = readExactLocked(4),
              let confData = readExactLocked(4) else {
            handleDeathLocked(); return nil
        }
        let len = lenData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let conf = confData.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        let textData: Data
        if len > 0 {
            guard let d = readExactLocked(Int(len)) else { handleDeathLocked(); return nil }
            textData = d
        } else {
            textData = Data()
        }
        return (String(data: textData, encoding: .utf8) ?? "", conf)
    }

    // worker умер (крэш whisper) — чистим и перезапустим на следующем запросе
    private func handleDeathLocked() {
        Log.asr.error("worker упал, перезапуск при следующем сегменте")
        cleanupLocked()
        _ = spawnLocked()
    }

    private func cleanupLocked() {
        try? toWorker?.close()
        try? fromWorker?.close()
        toWorker = nil
        fromWorker = nil
        proc = nil
        didStart = false
    }

    private func readU32Locked() -> UInt32? {
        readExactLocked(4)?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private func readExactLocked(_ count: Int) -> Data? {
        guard count > 0 else { return Data() }
        var buf = Data()
        while buf.count < count {
            guard let chunk = try? fromWorker?.read(upToCount: count - buf.count),
                  !chunk.isEmpty else { return nil }
            buf.append(chunk)
        }
        return buf
    }
}
