import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Снимает область экрана через ScreenCaptureKit (SCScreenshotManager, macOS 14+).
/// Пришло на смену deprecated CGWindowListCreateImage. Наш overlay с
/// sharingType=.none в кадр не попадает.
final class ScreenRegionCapturer {
    enum CaptureError: Error {
        case noDisplay
    }

    /// rect в глобальных координатах CG (origin сверху-слева главного экрана) —
    /// то, что отдаёт RegionSelector.
    func capture(rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = rect                    // кроп области (в точках, top-left)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        config.width = max(1, Int(rect.width * scale))   // Retina-разрешение для OCR
        config.height = max(1, Int(rect.height * scale))
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
    }
}
