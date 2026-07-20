import AppKit

/// Иконка в menu bar и меню приложения. UI, без логики.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private var historyItem: NSMenuItem?
    var onToggleOverlay: (() -> Void)?
    var onCaptureAndAsk: (() -> Void)?
    var onPermissions: (() -> Void)?
    var onToggleHistory: (() -> Void)?
    var onShowHistory: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onQuit: (() -> Void)?

    /// Отразить состояние согласия на сохранение истории (галочка).
    func setHistoryEnabled(_ enabled: Bool) {
        historyItem?.state = enabled ? .on : .off
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "AI"
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Снять и спросить  (⇧⌘A)",
                     action: #selector(captureAction), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Показать/скрыть overlay  (⇧⌘O)",
                     action: #selector(toggleAction), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        let hist = NSMenuItem(title: "Сохранять историю",
                              action: #selector(toggleHistoryAction), keyEquivalent: "")
        hist.target = self
        menu.addItem(hist)
        historyItem = hist
        menu.addItem(withTitle: "Показать историю…",
                     action: #selector(showHistoryAction), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Очистить историю",
                     action: #selector(clearHistoryAction), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Разрешения…",
                     action: #selector(permissionsAction), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Выход", action: #selector(quitAction), keyEquivalent: "q")
            .target = self
        statusItem.menu = menu
    }

    @objc private func captureAction() { onCaptureAndAsk?() }
    @objc private func toggleAction() { onToggleOverlay?() }
    @objc private func permissionsAction() { onPermissions?() }
    @objc private func toggleHistoryAction() { onToggleHistory?() }
    @objc private func showHistoryAction() { onShowHistory?() }
    @objc private func clearHistoryAction() { onClearHistory?() }
    @objc private func quitAction() { onQuit?() }
}

private extension NSMenu {
    @discardableResult
    func addItem(withTitle title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        addItem(item)
        return item
    }
}
