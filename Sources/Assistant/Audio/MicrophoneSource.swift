import AVFoundation

/// Источник звука с микрофона на AVAudioEngine.
/// Отдаёт сырые буферы наружу, ничего про ASR не знает.
/// System audio (ScreenCaptureKit / Core Audio tap) — отдельный источник, добавляется в v2
/// за тем же интерфейсом AudioSource.
protocol AudioSource {
    var source: TranscriptSegment.Source { get }
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

final class MicrophoneSource: AudioSource {
    let source: TranscriptSegment.Source = .microphone

    private let engine = AVAudioEngine()
    private var running = false

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // буфер ~100 мс; колбэк приходит на аудио-потоке — тут только передаём дальше
        input.installTap(onBus: 0, bufferSize: 1600, format: format) { buffer, _ in
            onBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        running = true
        Log.audio.info("microphone started, sr=\(format.sampleRate)")
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        Log.audio.info("microphone stopped")
    }
}
