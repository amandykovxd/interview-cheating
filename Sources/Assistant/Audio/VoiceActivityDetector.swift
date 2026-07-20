import Foundation

/// Адаптивный энергетический VAD. Не Silero (для него нужен апгрейд whisper),
/// но заметно устойчивее наивного фиксированного порога:
///  - плавающий шумовой пол (EMA энергии в тишине) -> порог подстраивается;
///  - минимальная длительность речи гасит короткие щелчки;
///  - hangover не рвёт фразу на коротких паузах.
final class VoiceActivityDetector {
    struct Config {
        var frameSize: Int = 480            // 30 мс при 16 kHz
        var hangoverFrames: Int = 15        // ~450 мс тишины закрывают сегмент
        var minSpeechFrames: Int = 3        // ~90 мс, чтобы не ловить щелчки
        var onsetMultiplier: Float = 3.0    // порог = шумовой пол * это
        var floorAdapt: Float = 0.05        // скорость адаптации пола
        var minThreshold: Float = 0.0008    // нижняя граница, чтоб не залипнуть в 0
    }

    enum Event {
        case speechStarted
        case speechEnded
    }

    private let config: Config
    private var noiseFloor: Float = 0.001
    private var inSpeech = false
    private var silenceRun = 0
    private var speechRun = 0

    init(config: Config = Config()) {
        self.config = config
    }

    func process(_ frame: ArraySlice<Float>) -> Event? {
        let energy = rms(frame)
        let threshold = max(config.minThreshold, noiseFloor * config.onsetMultiplier)
        let voiced = energy > threshold

        if voiced {
            speechRun += 1
            silenceRun = 0
            if !inSpeech && speechRun >= config.minSpeechFrames {
                inSpeech = true
                return .speechStarted
            }
        } else {
            speechRun = 0
            if inSpeech {
                silenceRun += 1
                if silenceRun >= config.hangoverFrames {
                    inSpeech = false
                    silenceRun = 0
                    return .speechEnded
                }
            } else {
                // пол тянем только в тишине, чтобы речь его не задирала
                noiseFloor = (1 - config.floorAdapt) * noiseFloor + config.floorAdapt * energy
            }
        }
        return nil
    }

    func reset() {
        inSpeech = false
        silenceRun = 0
        speechRun = 0
        noiseFloor = 0.001
    }

    private func rms(_ frame: ArraySlice<Float>) -> Float {
        guard !frame.isEmpty else { return 0 }
        var sum: Float = 0
        for s in frame { sum += s * s }
        return (sum / Float(frame.count)).squareRoot()
    }
}
