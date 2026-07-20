import AppKit

/// Выделение области экрана мышью, как в системном скриншоте.
/// Показывает полноэкранное затемнение, пользователь тянет прямоугольник,
/// на отпускании возвращает область. Escape — отмена.
@MainActor
final class RegionSelector {
    private var window: SelectionWindow?
    private var completion: ((CGRect?) -> Void)?

    /// rect возвращается в глобальных координатах CG (origin сверху-слева) —
    /// готов к передаче в ScreenRegionCapturer.
    func selectRegion(_ completion: @escaping (CGRect?) -> Void) {
        guard window == nil, let screen = NSScreen.main else {
            completion(nil)
            return
        }
        self.completion = completion
        let win = SelectionWindow(screen: screen)
        win.onFinish = { [weak self] rect in self?.finish(rect) }
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func finish(_ rect: CGRect?) {
        window?.orderOut(nil)
        window = nil
        let done = completion
        completion = nil
        done?(rect)
    }
}

/// Полноэкранное окно поверх всего, ловит клавиатуру (Escape) и мышь.
private final class SelectionWindow: NSPanel {
    var onFinish: ((CGRect?) -> Void)?
    private let screenFrame: NSRect

    init(screen: NSScreen) {
        screenFrame = screen.frame
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver              // выше overlay и обычных окон
        ignoresMouseEvents = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onSelect = { [weak self] viewRect in
            self?.onFinish?(self?.toCGGlobal(viewRect))
        }
        view.onCancel = { [weak self] in self?.onFinish?(nil) }
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    // view-координаты (снизу-вверх) -> глобальные CG (сверху-вниз главного экрана)
    private func toCGGlobal(_ viewRect: NSRect) -> CGRect {
        let globalX = screenFrame.minX + viewRect.minX
        let globalYBottom = screenFrame.minY + viewRect.minY
        let cgY = screenFrame.height - (globalYBottom + viewRect.height)
        return CGRect(x: globalX, y: cgY, width: viewRect.width, height: viewRect.height)
    }
}

private final class SelectionView: NSView {
    var onSelect: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        dirtyRect.fill()

        guard let rect = selectionRect() else { return }
        // вырезаем выбранную область из затемнения
        NSColor.clear.setFill()
        rect.fill(using: .clear)
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { start = nil; current = nil }
        guard let rect = selectionRect(), rect.width > 4, rect.height > 4 else {
            onCancel?()
            return
        }
        onSelect?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {   // Escape
            onCancel?()
        }
    }

    private func selectionRect() -> NSRect? {
        guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y),
                      width: abs(s.x - c.x), height: abs(s.y - c.y))
    }
}
