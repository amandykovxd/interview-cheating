import ApplicationServices
import AppKit

final class HotkeyService {
    enum Action {
        case captureAndAsk
        case toggleOverlay
    }

    private var handlers: [Action: () -> Void] = [:]
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func onAction(_ action: Action, _ handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    func start() {
        guard eventTap == nil else { return }

        if !requestAccessibilityAccess() {
            Log.app.error("hotkeys need Accessibility permission")
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .keyDown {
                    service.handle(event)
                } else if type == .tapDisabledByTimeout, let tap = service.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            Log.app.error("hotkey event tap creation failed")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    deinit {
        stop()
    }

    private func requestAccessibilityAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func handle(_ event: CGEvent) {
        let flags = event.flags
        guard flags.contains(.maskCommand),
              flags.contains(.maskShift),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate) else {
            return
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let action: Action?
        switch keyCode {
        case 0:
            action = .captureAndAsk
        case 31:
            action = .toggleOverlay
        default:
            action = nil
        }

        if let action {
            DispatchQueue.main.async { [weak self] in
                self?.handlers[action]?()
            }
        }
    }
}
