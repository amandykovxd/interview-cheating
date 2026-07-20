import AVFoundation

/// Связывает источник -> ресемплер -> VAD -> накопление сегмента.
/// На выходе AsyncStream<AudioSegment>: куски речи с таймстампами, без тишины.
///
/// Обработка вынесена на отдельную очередь: аудио-колбэк только кладёт буфер,
/// разбор и VAD идут вне realtime-потока.
final class AudioPipeline {
    private let sourceProvider: AudioSource
    private let processingQueue = DispatchQueue(label: "audio.pipeline", qos: .userInitiated)

    private var resampler: AudioResampler?
    private let vad = VoiceActivityDetector()

    private var pending: [Float] = []        // накопитель текущего сегмента
    private var carry: [Float] = []          // остаток кадра между буферами
    private var segmentStart: TimeInterval = 0
    private var lastPartialCount = 0         // сколько сэмплов было на прошлом partial

    private var continuation: AsyncStream<AudioSegment>.Continuation?

    // Диагностика: пришёл ли хоть один буфер. Для системного звука нулевой
    // приход обычно значит отсутствие разрешения на запись звука.
    private(set) var didReceiveInput = false

    init(source: AudioSource) {
        self.sourceProvider = source
    }

    func start() throws -> AsyncStream<AudioSegment> {
        // сбрасываем состояние VAD/накопителей, но НЕ часы: таймлайн монотонный
        // на всё время работы, чтобы окно контекста корректно старело между
        // сессиями "Слушать" (start/stop)
        vad.reset()
        pending.removeAll()
        carry.removeAll()
        lastPartialCount = 0
        didReceiveInput = false
        let stream = AsyncStream<AudioSegment> { continuation in
            self.continuation = continuation
        }
        try sourceProvider.start { [weak self] buffer in
            self?.processingQueue.async {
                self?.handle(buffer)
            }
        }
        return stream
    }

    func stop() {
        sourceProvider.stop()
        continuation?.finish()
        continuation = nil
    }

    // Разбор буфера вне realtime-потока.
    private func handle(_ buffer: AVAudioPCMBuffer) {
        didReceiveInput = true
        if resampler == nil {
            resampler = AudioResampler(inputFormat: buffer.format)
        }
        guard let samples = resampler?.resample(buffer) else { return }

        carry.append(contentsOf: samples)
        let frameSize = 480
        var offset = 0

        while carry.count - offset >= frameSize {
            let frame = carry[offset..<offset + frameSize]
            switch vad.process(frame) {
            case .speechStarted:
                if pending.isEmpty {
                    segmentStart = now()
                    lastPartialCount = 0
                }
                pending.append(contentsOf: frame)
            case .speechEnded:
                pending.append(contentsOf: frame)
                emitSegment(isPartial: false)     // финал
            case nil:
                if !pending.isEmpty {
                    pending.append(contentsOf: frame)
                    emitPartialIfDue()             // промежуточный вывод по ходу речи
                }
            }
            offset += frameSize
        }
        carry.removeFirst(offset)
    }

    // Пока речь идёт, раз в ~partialInterval секунд отдаём накопленное как partial,
    // чтобы текст появлялся не только после паузы.
    private func emitPartialIfDue() {
        let interval = Int(AudioResampler.targetSampleRate * 1.2)
        if pending.count - lastPartialCount >= interval {
            lastPartialCount = pending.count
            emitSegment(isPartial: true)
        }
    }

    private func emitSegment(isPartial: Bool) {
        guard !pending.isEmpty else { return }
        let segment = AudioSegment(
            samples: pending,
            sampleRate: AudioResampler.targetSampleRate,
            source: sourceProvider.source,
            start: segmentStart,
            end: now(),
            isPartial: isPartial
        )
        if !isPartial {
            pending.removeAll(keepingCapacity: true)   // финал очищает накопитель
            lastPartialCount = 0
        }
        continuation?.yield(segment)
    }

    // Монотонные часы от старта процесса: не сбрасываются при stop/start,
    // не прыгают при переводе системного времени.
    private func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
