import AVFoundation
import XCTest
@testable import Assistant

/// Интеграция изоляции: реально спавним WhisperWorker и гоняем звук через процесс.
/// Пропуск, если модель/бинарь worker не найдены.
final class ProcessASREngineTests: XCTestCase {
    private var modelURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Assistant/Models/ggml-tiny.bin")
    }

    // WhisperWorker лежит рядом с тестовым бинарём в .build/<config>/
    private var workerURL: URL? {
        let dir = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let candidate = dir.appendingPathComponent("WhisperWorker")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    func testTranscribesThroughSubprocess() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: modelURL.path), "нет модели")
        let worker = try XCTUnwrap(workerURL, "не найден бинарь WhisperWorker")

        let engine = ProcessASREngine(workerURL: worker, modelPath: modelURL)
        XCTAssertTrue(engine.start(), "worker не поднялся")
        defer { engine.shutdown() }

        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "speech", withExtension: "wav"))
        let samples = try Self.loadSamples(fixture)
        let segment = AudioSegment(samples: samples, sampleRate: AudioResampler.targetSampleRate,
                                   source: .system, start: 0,
                                   end: Double(samples.count) / AudioResampler.targetSampleRate)

        var text = ""
        for await r in engine.transcribe(segment) { text += r.text }
        print("worker распознал: '\(text)'")
        XCTAssertTrue(text.lowercased().contains("kubernetes") || text.lowercased().contains("docker"),
                      "через процесс не распозналось: \(text)")
    }

    func testRestartsAfterWorkerKilled() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: modelURL.path), "нет модели")
        let worker = try XCTUnwrap(workerURL, "не найден бинарь WhisperWorker")

        let engine = ProcessASREngine(workerURL: worker, modelPath: modelURL)
        XCTAssertTrue(engine.start())
        defer { engine.shutdown() }

        // грубо роняем worker
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-9", "-f", "WhisperWorker"])
        try await Task.sleep(nanoseconds: 300_000_000)

        // следующий запрос должен перезапустить worker и всё равно распознать
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "speech", withExtension: "wav"))
        let samples = try Self.loadSamples(fixture)
        let segment = AudioSegment(samples: samples, sampleRate: AudioResampler.targetSampleRate,
                                   source: .system, start: 0, end: 1)
        // первый запрос ловит смерть и перезапускает (может вернуть пусто),
        // второй должен отработать на свежем worker
        for await _ in engine.transcribe(segment) {}
        var text = ""
        for await r in engine.transcribe(segment) { text += r.text }
        XCTAssertFalse(text.isEmpty, "после перезапуска worker не ожил")
    }

    private static func loadSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate,
                               channels: 1, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let ch = buf.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
    }
}
