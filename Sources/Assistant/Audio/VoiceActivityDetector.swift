import Foundation

/// Простой энергетический VAD с гистерезисом. Задача — не гнать тишину в ASR
/// и резать поток на сегменты речи. На v2 заменяется на Silero через Core ML.
final class VoiceActivityDetector {
    struct Config {
        var frameSize: Int = 480            // 30 мс при 16 kHz
        var energyThreshold: Float = 0.0015 // порог RMS, подбирается под микрофон
        var hangoverFrames: Int = 15        // ~450 мс тишины закрывают сегмент
    }

    enum Event {
        case speechStarted
        case speechEnded
    }

    private let config: Config
    private var inSpeech = false
    private var silenceRun = 0

    init(config: Config = Config()) {
        self.config = config
    }

    /// Скармливаем кадр, получаем событие перехода (или nil, если состояние не сменилось).
    func process(_ frame: ArraySlice<Float>) -> Event? {
        let energy = rms(frame)
        let voiced = energy > config.energyThreshold

        if voiced {
            silenceRun = 0
            if !inSpeech {
                inSpeech = true
                return .speechStarted
            }
        } else if inSpeech {
            silenceRun += 1
            if silenceRun >= config.hangoverFrames {
                inSpeech = false
                silenceRun = 0
                return .speechEnded
            }
        }
        return nil
    }

    func reset() {
        inSpeech = false
        silenceRun = 0
    }

    private func rms(_ frame: ArraySlice<Float>) -> Float {
        guard !frame.isEmpty else { return 0 }
        var sum: Float = 0
        for s in frame { sum += s * s }
        return (sum / Float(frame.count)).squareRoot()
    }
}
