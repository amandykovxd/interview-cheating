import AppKit
import Carbon.HIToolbox

/// Глобальные горячие клавиши через Carbon RegisterEventHotKey.
/// Этот путь не требует Accessibility (в отличие от перехвата CGEvent).
final class HotkeyService {
    enum Action: UInt32 {
        case captureAndAsk = 1   // снять область + спросить LLM
        case toggleOverlay = 2
    }

    private var handlers: [Action: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    func onAction(_ action: Action, _ handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    func start() {
        installDispatcher()
        // Cmd+Shift+A — снять и спросить, Cmd+Shift+O — показать/скрыть overlay
        register(action: .captureAndAsk, keyCode: UInt32(kVK_ANSI_A), modifiers: cmdShift)
        register(action: .toggleOverlay, keyCode: UInt32(kVK_ANSI_O), modifiers: cmdShift)
    }

    private var cmdShift: UInt32 { UInt32(cmdKey | shiftKey) }

    private func register(action: Action, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x41535354), id: action.rawValue) // 'ASST'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRefs.append(ref)
        } else {
            Log.app.error("hotkey register failed: \(status)")
        }
    }

    private func installDispatcher() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            if let action = Action(rawValue: hkID.id) {
                DispatchQueue.main.async { service.handlers[action]?() }
            }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }
}
