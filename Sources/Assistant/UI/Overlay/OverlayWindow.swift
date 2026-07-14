import AppKit

/// Прозрачная панель поверх окон. NSPanel (не NSWindow), чтобы не воровать фокус.
final class OverlayWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar                       // поверх обычных окон, но ниже системных алертов
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isFloatingPanel = true
        isMovableByWindowBackground = true
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Экспериментальное скрытие от записи экрана.
    /// ВАЖНО: sharingType=.none убирает окно из большинства ШТАТНЫХ путей захвата,
    /// но это не гарантия. Поведение менялось между версиями macOS, аппаратный захват
    /// (грабер/камера) окно видит всегда. Не обещаем невидимость.
    func setHiddenFromCapture(_ hidden: Bool) {
        sharingType = hidden ? .none : .readOnly
    }
}
