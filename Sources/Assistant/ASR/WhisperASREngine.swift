import Foundation
import WhisperCore

/// Распознавание через whisper. Контекст модели тяжёлый — грузим один раз и держим.
/// whisper_full не потокобезопасен для одного контекста, поэтому все вызовы
/// идут через один serial queue.
final class WhisperASREngine: ASREngine {
    struct Config {
        /// "auto" — не форсим язык: иначе русские фразы с английскими терминами
        /// начинают транслитерироваться в кириллицу.
        var language: String = "auto"
        /// Подсказка декодеру: поднимает точность на тех-лексике и аббревиатурах.
        var initialPrompt: String? =
            "Разговор про программирование: Swift, Kubernetes, Docker, PostgreSQL, "
            + "API, backend, deploy, pull request, code review."
        var threads: Int32 = 4
    }

    private let ctx: OpaquePointer
    private let config: Config
    private let queue = DispatchQueue(label: "asr.whisper", qos: .userInitiated)

    // Занятость: partial-куски отбрасываем, если whisper уже считает, иначе
    // при потоковом режиме очередь распухнет. Финалы ждут очередь всегда.
    private let busyLock = NSLock()
    private var isBusy = false

    // Слишком короткие куски whisper превращает в мусор — такие пропускаем.
    private let minSamples = Int(AudioResampler.targetSampleRate * 0.3)

    var isAvailable: Bool { true }

    init?(modelPath: URL, config: Config = Config()) {
        var params = whisper_context_default_params()
        params.use_gpu = true       // Metal на Apple Silicon
        params.flash_attn = false

        guard let ctx = whisper_init_from_file_with_params(modelPath.path, params) else {
            Log.asr.error("не удалось загрузить модель: \(modelPath.lastPathComponent)")
            return nil
        }
        self.ctx = ctx
        self.config = config
        Log.asr.info("whisper готов: \(modelPath.lastPathComponent)")
    }

    deinit {
        whisper_free(ctx)
    }

    func transcribe(_ segment: AudioSegment) -> AsyncStream<ASRResult> {
        AsyncStream { continuation in
            guard segment.samples.count >= minSamples else {
                continuation.finish()
                return
            }
            // partial отбрасываем, если движок занят; финал всегда встаёт в очередь
            if segment.isPartial, !beginIfFree() {
                continuation.finish()
                return
            }
            if !segment.isPartial { markBusy() }

            queue.async { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                defer {
                    self.clearBusy()
                    continuation.finish()
                }
                let started = DispatchTime.now()
                if let res = self.run(samples: segment.samples) {
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
                    Log.asr.debug("asr \(segment.isPartial ? "partial" : "final") \(ms, format: .fixed(precision: 0))ms")
                    continuation.yield(ASRResult(text: res.text,
                                                 isFinal: !segment.isPartial,
                                                 confidence: res.confidence))
                }
            }
        }
    }

    // MARK: - Занятость

    private func beginIfFree() -> Bool {
        busyLock.lock(); defer { busyLock.unlock() }
        if isBusy { return false }
        isBusy = true
        return true
    }

    private func markBusy() {
        busyLock.lock(); isBusy = true; busyLock.unlock()
    }

    private func clearBusy() {
        busyLock.lock(); isBusy = false; busyLock.unlock()
    }

    // MARK: - Внутреннее

    private func run(samples: [Float]) -> ASRResult? {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = config.threads
        params.translate = false
        params.no_context = true        // сегменты независимы, VAD уже нарезал
        params.no_timestamps = true
        params.single_segment = false
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.suppress_blank = true
        params.temperature = 0

        // C-строки должны жить всё время вызова whisper_full
        return config.language.withCString { lang -> ASRResult? in
            params.language = lang
            if let prompt = config.initialPrompt {
                return prompt.withCString { promptPtr in
                    params.initial_prompt = promptPtr
                    return execute(params: params, samples: samples)
                }
            }
            return execute(params: params, samples: samples)
        }
    }

    private func execute(params: whisper_full_params, samples: [Float]) -> ASRResult? {
        let code = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard code == 0 else {
            Log.asr.error("whisper_full вернул \(code)")
            return nil
        }
        return collectResult()
    }

    private func collectResult() -> ASRResult? {
        var text = ""
        var probSum: Float = 0
        var probCount = 0

        for i in 0..<whisper_full_n_segments(ctx) {
            if let cstr = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: cstr)
            }
            for t in 0..<whisper_full_n_tokens(ctx, i) {
                probSum += whisper_full_get_token_p(ctx, i, t)
                probCount += 1
            }
        }

        let cleaned = Self.clean(text)
        guard !cleaned.isEmpty else { return nil }

        let confidence = probCount > 0 ? probSum / Float(probCount) : 0
        return ASRResult(text: cleaned, isFinal: true, confidence: confidence)
    }

    /// Whisper на тишине и шуме любит выдавать маркеры вроде [BLANK_AUDIO] или
    /// (музыка) — в контекст такое пускать незачем.
    private static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let noise = ["[BLANK_AUDIO]", "[MUSIC]", "[SOUND]", "[NOISE]",
                     "(музыка)", "(тишина)", "[музыка]", "*музыка*"]
        for marker in noise {
            text = text.replacingOccurrences(of: marker, with: "",
                                             options: .caseInsensitive)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
