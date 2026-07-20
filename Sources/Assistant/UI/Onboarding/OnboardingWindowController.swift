import AppKit
import SwiftUI

/// Обычное окно (в отличие от overlay может стать key) под онбординг.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let permissions: PermissionsService
    var onClosed: (() -> Void)?

    init(permissions: PermissionsService) {
        self.permissions = permissions
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let vm = OnboardingViewModel(permissions: permissions)
        vm.onClose = { [weak self] in self?.close() }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Assistant"
        win.titlebarAppearsTransparent = true
        win.center()
        win.contentView = NSHostingView(rootView: OnboardingView(model: vm))
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
        onClosed?()
    }
}
