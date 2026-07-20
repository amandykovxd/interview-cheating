import AVFoundation
import CoreAudio

/// Системный звук через Core Audio process tap (macOS 14.2+).
/// Это audio-only путь: не требует разрешения на запись экрана, в отличие от
/// ScreenCaptureKit. Собеседник в созвоне звучит именно здесь, а не в микрофоне,
/// поэтому его реплики уходят как .system ("Собеседник").
///
/// Схема: глобальный tap -> приватный aggregate device -> IOProc -> буферы наружу.
final class SystemAudioSource: AudioSource {
    let source: TranscriptSegment.Source = .system

    enum SystemAudioError: Error {
        case unsupportedOS
        case tapFailed(OSStatus)
        case aggregateFailed(OSStatus)
        case ioProcFailed(OSStatus)
        case noFormat
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var format: AVAudioFormat?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private let ioQueue = DispatchQueue(label: "audio.system.io", qos: .userInitiated)
    private var running = false

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard #available(macOS 14.2, *) else { throw SystemAudioError.unsupportedOS }
        guard !running else { return }
        self.onBuffer = onBuffer

        // 1. описание tap: глобальный микс всего системного звука, никого не исключаем
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.isPrivate = true
        desc.muteBehavior = .unmuted        // только слушаем, вывод не глушим
        desc.name = "Assistant System Tap"

        // 2. создаём tap
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(desc, &tap)
        guard status == noErr else { throw SystemAudioError.tapFailed(status) }
        tapID = tap

        // 3. формат tap -> из него делаем AVAudioFormat для оборачивания буферов
        guard var asbd = try? readTapFormat(tap),
              let fmt = AVAudioFormat(streamDescription: &asbd) else {
            cleanup()
            throw SystemAudioError.noFormat
        }
        format = fmt

        // 4. приватный aggregate device, включающий наш tap
        let aggUID = UUID().uuidString
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Assistant System Aggregate",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: desc.uuid.uuidString]
            ]
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &agg)
        guard status == noErr else {
            cleanup()
            throw SystemAudioError.aggregateFailed(status)
        }
        aggregateID = agg

        // 5. IOProc: колбэк реального времени, только копируем буфер и отдаём наружу
        var proc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, agg, ioQueue) {
            [weak self] _, inInputData, _, _, _ in
            self?.handleIO(inInputData)
        }
        guard status == noErr, let proc else {
            cleanup()
            throw SystemAudioError.ioProcFailed(status)
        }
        procID = proc

        status = AudioDeviceStart(agg, proc)
        guard status == noErr else {
            cleanup()
            throw SystemAudioError.ioProcFailed(status)
        }
        running = true
        Log.audio.info("system audio tap started, sr=\(fmt.sampleRate)")
    }

    func stop() {
        guard running else { return }
        cleanup()
        running = false
        Log.audio.info("system audio tap stopped")
    }

    // MARK: - Внутреннее

    private func handleIO(_ inInputData: UnsafePointer<AudioBufferList>) {
        guard let format else { return }
        // оборачиваем ABL без копирования, только чтобы узнать длину в кадрах
        guard let view = AVAudioPCMBuffer(pcmFormat: format,
                                          bufferListNoCopy: inInputData,
                                          deallocator: nil),
              view.frameLength > 0 else { return }

        // память ABL живёт только на время колбэка — копируем в свой буфер,
        // который переживёт async-обработку в AudioPipeline
        guard let copy = AVAudioPCMBuffer(pcmFormat: format,
                                          frameCapacity: view.frameLength) else { return }
        copy.frameLength = view.frameLength

        // копируем сырой ABL буфер-в-буфер: работает и для interleaved (tap отдаёт
        // именно его: стерео float32 packed), и для non-interleaved
        let inList = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inInputData))
        let outList = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard inList.count == outList.count else { return }
        for i in 0..<inList.count {
            guard let inData = inList[i].mData, let outData = outList[i].mData else { continue }
            let bytes = min(Int(inList[i].mDataByteSize), Int(outList[i].mDataByteSize))
            memcpy(outData, inData, bytes)
        }
        onBuffer?(copy)
    }

    private func readTapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd)
        guard status == noErr else { throw SystemAudioError.tapFailed(status) }
        return asbd
    }

    private func cleanup() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = kAudioObjectUnknown
        }
        format = nil
    }

    deinit {
        cleanup()
    }
}
