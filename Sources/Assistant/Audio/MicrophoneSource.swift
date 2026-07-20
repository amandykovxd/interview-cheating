import AVFoundation

/// Источник звука. Микрофон и системный tap реализуют один интерфейс,
/// чтобы вставать в один и тот же AudioPipeline.
protocol AudioSource {
    var source: TranscriptSegment.Source { get }
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

/// Микрофон на AVAudioEngine. Отдаёт сырые буферы наружу, про ASR не знает.
final class MicrophoneSource: AudioSource {
    let source: TranscriptSegment.Source = .microphone

    private let engine = AVAudioEngine()
    private var running = false
    private let echoCancellation: Bool

    init(echoCancellation: Bool = true) {
        self.echoCancellation = echoCancellation
    }

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !running else { return }
        let input = engine.inputNode

        // Системный эхоподавитель (тот же, что в звонках): берёт то, что играет
        // в динамики, как референс и вычитает из микрофона. Убирает голос
        // собеседника из колонок, чтобы он не попал в микрофон как "Я".
        // Ставить до старта движка; формат входа после включения меняется.
        if echoCancellation {
            do {
                try input.setVoiceProcessingEnabled(true)
            } catch {
                Log.audio.error("voice processing off: \(error.localizedDescription)")
            }
        }

        let format = input.outputFormat(forBus: 0)
        // буфер ~100 мс; колбэк на аудио-потоке — тут только передаём дальше
        input.installTap(onBus: 0, bufferSize: 1600, format: format) { buffer, _ in
            onBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        running = true
        let aec = echoCancellation
        Log.audio.info("microphone started, sr=\(format.sampleRate), aec=\(aec)")
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        Log.audio.info("microphone stopped")
    }
}
