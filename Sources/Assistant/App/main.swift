import AppKit

/// Точка входа. macOS-стиль: NSApplication + делегат, без iOS-style @main App.
/// accessory-режим: живём в menu bar, без иконки в Dock.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
