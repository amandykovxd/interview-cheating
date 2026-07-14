import AVFoundation

/// Приводит любой входной формат к 16 kHz mono float32 — то, что ест ASR.
/// Конвертим один раз на входе, дальше по пайплайну гоняем только целевой формат.
final class AudioResampler {
    static let targetSampleRate: Double = 16_000

    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat

    init?(inputFormat: AVAudioFormat) {
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let converter = AVAudioConverter(from: inputFormat, to: target) else {
            return nil
        }
        self.targetFormat = target
        self.converter = converter
    }

    /// Возвращает float-сэмплы в целевом формате. nil — если конверсия не удалась.
    func resample(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let ratio = Self.targetSampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            // отдаём вход один раз, потом сигналим, что данных больше нет
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil,
              let channel = out.floatChannelData?[0] else {
            if let error { Log.audio.error("resample failed: \(error.localizedDescription)") }
            return nil
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }
}
