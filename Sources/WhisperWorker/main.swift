import Foundation
import WhisperCore

// Отдельный процесс распознавания. Изолирует крэши whisper от UI: если модель
// уронит процесс, родитель это переживёт и перезапустит worker.
//
// Протокол (LE), всё бинарное, stdout только под кадры:
//   handshake worker->parent: u32 status (0=fail, 1=metal, 3=coreml)
//   request  parent->worker:  u32 nSamples, u32 flags(bit0=partial), f32[nSamples]
//                             nSamples == 0xFFFFFFFF => завершение
//   response worker->parent:  u32 textLen, f32 confidence, utf8[textLen]

// --- перехват логов whisper (для определения Core ML), чтобы не сорить в stdout ---
enum WLog {
    static var text = ""
    static func install() {
        whisper_log_set({ _, msg, _ in
            if let msg { WLog.text += String(cString: msg) }
        }, nil)
    }
}

let stdinFH = FileHandle.standardInput
let stdoutFH = FileHandle.standardOutput

func readExact(_ count: Int) -> Data? {
    guard count > 0 else { return Data() }
    var buf = Data()
    while buf.count < count {
        guard let chunk = try? stdinFH.read(upToCount: count - buf.count), !chunk.isEmpty else {
            return nil   // EOF
        }
        buf.append(chunk)
    }
    return buf
}

func readU32() -> UInt32? {
    guard let d = readExact(4) else { return nil }
    return d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
}

func writeStatus(_ v: UInt32) {
    var x = v
    stdoutFH.write(Data(bytes: &x, count: 4))
}

func writeResponse(_ text: String, _ confidence: Float) {
    let bytes = Array(text.utf8)
    var len = UInt32(bytes.count)
    var conf = confidence
    var out = Data()
    out.append(Data(bytes: &len, count: 4))
    out.append(Data(bytes: &conf, count: 4))
    out.append(contentsOf: bytes)
    stdoutFH.write(out)
}

// --- инициализация модели ---
WLog.install()
guard CommandLine.arguments.count >= 2 else { writeStatus(0); exit(2) }
let modelPath = CommandLine.arguments[1]

var cparams = whisper_context_default_params()
cparams.use_gpu = true
guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
    writeStatus(0)
    exit(3)
}
let coreml = WLog.text.contains("Core ML model loaded")
writeStatus(coreml ? 3 : 1)

let initialPrompt =
    "Разговор про программирование: Swift, Kubernetes, Docker, PostgreSQL, "
    + "API, backend, deploy, pull request, code review."

func transcribe(_ samples: [Float]) -> (String, Float) {
    var p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    p.n_threads = 4
    p.translate = false
    p.no_context = true
    p.no_timestamps = true
    p.print_special = false
    p.print_progress = false
    p.print_realtime = false
    p.print_timestamps = false
    p.suppress_blank = true
    p.temperature = 0

    return "auto".withCString { lang -> (String, Float) in
        p.language = lang
        return initialPrompt.withCString { prompt -> (String, Float) in
            p.initial_prompt = prompt
            let code = samples.withUnsafeBufferPointer {
                whisper_full(ctx, p, $0.baseAddress, Int32($0.count))
            }
            guard code == 0 else { return ("", 0) }

            var text = ""
            var probSum: Float = 0, probCount = 0
            for i in 0..<whisper_full_n_segments(ctx) {
                if let c = whisper_full_get_segment_text(ctx, i) { text += String(cString: c) }
                for t in 0..<whisper_full_n_tokens(ctx, i) {
                    probSum += whisper_full_get_token_p(ctx, i, t); probCount += 1
                }
            }
            let conf = probCount > 0 ? probSum / Float(probCount) : 0
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), conf)
        }
    }
}

// --- цикл обработки запросов ---
while true {
    guard let n = readU32() else { break }        // EOF -> выходим
    if n == 0xFFFF_FFFF { break }                  // явное завершение
    guard readU32() != nil,                        // flags (partial/final) worker не различает
          let bytes = readExact(Int(n) * 4) else { break }
    let samples = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let (text, conf) = transcribe(samples)
    writeResponse(text, conf)
}

whisper_free(ctx)
