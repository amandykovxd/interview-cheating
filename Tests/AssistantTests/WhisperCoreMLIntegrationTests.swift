import XCTest
@testable import Assistant

/// Интеграция: доказываем, что Core ML энкодер реально грузится (а не только
/// компилируется). Наблюдаемость — через флаг usesCoreML, который движок ставит
/// по логам whisper. Пропуск, если модели не скачаны.
final class WhisperCoreMLIntegrationTests: XCTestCase {
    private var modelsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Assistant/Models")
    }
    private var tinyBin: URL { modelsDir.appendingPathComponent("ggml-tiny.bin") }
    private var tinyEncoder: URL { modelsDir.appendingPathComponent("ggml-tiny-encoder.mlmodelc") }

    func testCoreMLEncoderLoadsWhenPresent() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: tinyBin.path),
                          "ggml-tiny.bin не скачан")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: tinyEncoder.path),
                          "Core ML энкодер не скачан")
        let engine = try XCTUnwrap(WhisperASREngine(modelPath: tinyBin))
        XCTAssertTrue(engine.usesCoreML, "Core ML энкодер не загрузился")
    }

    func testInitFallsBackWithoutEncoder() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: tinyBin.path),
                          "ggml-tiny.bin не скачан")
        // копируем .bin в temp без энкодера рядом — движок должен подняться на Metal
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nocoreml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bin = tmp.appendingPathComponent("ggml-tiny.bin")
        try FileManager.default.copyItem(at: tinyBin, to: bin)

        let engine = try XCTUnwrap(WhisperASREngine(modelPath: bin))
        XCTAssertFalse(engine.usesCoreML, "без энкодера usesCoreML должен быть false")
    }
}
