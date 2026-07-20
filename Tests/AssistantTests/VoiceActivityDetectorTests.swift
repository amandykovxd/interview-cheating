import XCTest
@testable import Assistant

final class VoiceActivityDetectorTests: XCTestCase {
    private func frame(_ amp: Float, _ n: Int = 480) -> ArraySlice<Float> {
        // знакопеременный сигнал заданной амплитуды -> нужный RMS
        ArraySlice((0..<n).map { $0 % 2 == 0 ? amp : -amp })
    }

    func testDetectsSpeechAfterMinFrames() {
        let vad = VoiceActivityDetector()
        // тишина
        for _ in 0..<20 { _ = vad.process(frame(0.0001)) }
        // громкая речь: событие приходит после нескольких кадров, не мгновенно
        var started = false
        for _ in 0..<10 {
            if vad.process(frame(0.2)) == .speechStarted { started = true; break }
        }
        XCTAssertTrue(started)
    }

    func testEndsAfterHangover() {
        let vad = VoiceActivityDetector()
        for _ in 0..<20 { _ = vad.process(frame(0.0001)) }
        for _ in 0..<10 { _ = vad.process(frame(0.2)) }
        var ended = false
        for _ in 0..<40 {
            if vad.process(frame(0.0001)) == .speechEnded { ended = true; break }
        }
        XCTAssertTrue(ended)
    }

    func testAdaptsToHigherNoiseFloor() {
        // при высоком шуме тот же уровень «речи» не должен триггерить —
        // порог адаптивный, а не фиксированный
        let vad = VoiceActivityDetector()
        for _ in 0..<60 { _ = vad.process(frame(0.05)) }   // стабильный шум
        var triggered = false
        for _ in 0..<10 {
            if vad.process(frame(0.06)) == .speechStarted { triggered = true }
        }
        XCTAssertFalse(triggered, "шумовой пол не адаптировался")
    }
}
