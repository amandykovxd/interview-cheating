import XCTest
@testable import Assistant

/// TDD: имена и пути Core ML энкодера. Чистая логика, без сети.
final class WhisperModelCoreMLTests: XCTestCase {
    func testEncoderFileName() {
        XCTAssertEqual(WhisperModel.tiny.coreMLEncoderName, "ggml-tiny-encoder.mlmodelc")
        XCTAssertEqual(WhisperModel.base.coreMLEncoderName, "ggml-base-encoder.mlmodelc")
        XCTAssertEqual(WhisperModel.small.coreMLEncoderName, "ggml-small-encoder.mlmodelc")
    }

    func testEncoderZipName() {
        XCTAssertEqual(WhisperModel.tiny.coreMLZipName, "ggml-tiny-encoder.mlmodelc.zip")
    }

    func testEncoderDownloadURL() {
        XCTAssertEqual(
            WhisperModel.base.coreMLDownloadURL.absoluteString,
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-encoder.mlmodelc.zip"
        )
    }

    func testStoreEncoderURLSitsNextToBin() async {
        let store = WhisperModelStore()
        let bin = await store.localURL(for: .tiny)
        let enc = await store.coreMLEncoderURL(for: .tiny)
        // энкодер лежит в той же папке, что и .bin (whisper ищет рядом)
        XCTAssertEqual(bin.deletingLastPathComponent(), enc.deletingLastPathComponent())
        XCTAssertEqual(enc.lastPathComponent, "ggml-tiny-encoder.mlmodelc")
    }
}
