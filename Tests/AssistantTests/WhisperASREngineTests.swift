import AVFoundation
import XCTest
@testable import Assistant

/// Интеграционный тест: гоняет настоящую модель на настоящем аудио.
/// Пропускается, если модель не скачана — чтобы обычный прогон оставался быстрым.
final class WhisperASREngineTests: XCTestCase {
    private var modelURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Assistant/Models/ggml-tiny.bin")
    }

    func testTranscribesRealSpeech() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: modelURL.path),
            "модель ggml-tiny.bin не скачана — пропускаем"
        )
        let fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "speech", withExtension: "wav")
        )
        let engine = try XCTUnwrap(WhisperASREngine(modelPath: modelURL))
        let samples = try Self.loadSamples(fixture)

        let segment = AudioSegment(
            samples: samples,
            sampleRate: AudioResampler.targetSampleRate,
            source: .microphone,
            start: 0,
            end: Double(samples.count) / AudioResampler.targetSampleRate
        )

        var text = ""
        var confidence: Float = 0
        for await result in engine.transcribe(segment) {
            text += result.text
            confidence = result.confidence
        }

        print("распознано: '\(text)' (confidence \(confidence))")
        XCTAssertFalse(text.isEmpty, "распознавание вернуло пустой текст")
        // в сэмпле сказано про Kubernetes и Docker — проверяем, что термины ловятся
        let lower = text.lowercased()
        XCTAssertTrue(lower.contains("kubernetes") || lower.contains("docker"),
                      "английские термины не распознались, получили: \(text)")
        XCTAssertGreaterThan(confidence, 0)
    }

    func testShortSegmentIsSkipped() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: modelURL.path),
            "модель ggml-tiny.bin не скачана — пропускаем"
        )
        let engine = try XCTUnwrap(WhisperASREngine(modelPath: modelURL))
        // 100 мс — короче порога, движок не должен ничего отдать
        let segment = AudioSegment(
            samples: [Float](repeating: 0, count: 1600),
            sampleRate: AudioResampler.targetSampleRate,
            source: .microphone,
            start: 0,
            end: 0.1
        )
        var count = 0
        for await _ in engine.transcribe(segment) { count += 1 }
        XCTAssertEqual(count, 0)
    }

    func testMissingModelReturnsNil() {
        let engine = WhisperASREngine(modelPath: URL(fileURLWithPath: "/nope/missing.bin"))
        XCTAssertNil(engine, "на отсутствующей модели инициализация должна падать в nil")
    }

    private static func loadSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: file.fileFormat.sampleRate,
                                   channels: 1,
                                   interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                      frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let channel = buffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
