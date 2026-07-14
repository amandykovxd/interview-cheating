import AppKit
import SwiftUI

/// Держит окно overlay и хостит в нём SwiftUI-вью.
@MainActor
final class OverlayWindowController {
    let window: OverlayWindow
    let viewModel: OverlayViewModel

    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel
        self.window = OverlayWindow()
        let host = NSHostingView(rootView: OverlayView(model: viewModel))
        window.contentView = host
    }

    func show() {
        positionTopRight()
        window.orderFrontRegardless()   // показываем, не активируя приложение
    }

    func hide() {
        window.orderOut(nil)
    }

    func toggle() {
        window.isVisible ? hide() : show()
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 24
        let frame = window.frame
        let x = screen.visibleFrame.maxX - frame.width - margin
        let y = screen.visibleFrame.maxY - frame.height - margin
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
