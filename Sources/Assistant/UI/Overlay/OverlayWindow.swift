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

        // ключ панель получает только когда реально нужен ввод (клик по полю),
        // при обычном показе фокус у активного приложения не отбирается
        becomesKeyOnlyIfNeeded = true

        // по умолчанию прячем окно из штатного захвата экрана (см. оговорку ниже)
        sharingType = .none
    }

    // true — иначе текстовые поля (ввод/вставка ключа) не получают клавиатуру.
    // Благодаря .nonactivatingPanel панель становится key, не активируя приложение.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Скрытие от записи экрана.
    /// ВАЖНО: sharingType=.none убирает окно из большинства ШТАТНЫХ путей захвата
    /// (скриншот, screen recording, шаринг через системные API), но это НЕ гарантия.
    /// Поведение менялось между версиями macOS, аппаратный захват (грабер/камера)
    /// и часть путей ScreenCaptureKit окно всё равно видят. Не обещаем невидимость.
    func setHiddenFromCapture(_ hidden: Bool) {
        sharingType = hidden ? .none : .readOnly
    }
}
