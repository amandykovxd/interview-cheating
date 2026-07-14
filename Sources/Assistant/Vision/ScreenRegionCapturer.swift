import CoreGraphics
import Foundation

/// Снимает только заданную область экрана, а не весь дисплей.
/// На старте — CGWindowListCreateImage (простой путь). В v2 переезд на ScreenCaptureKit
/// ради совместимости с новыми версиями macOS и отзыва прав.
final class ScreenRegionCapturer {
    enum CaptureError: Error {
        case failed
    }

    /// rect в координатах экрана (глобальных, origin сверху-слева как у CG).
    func capture(rect: CGRect) throws -> CGImage {
        // nil-окно => композит всех окон в пределах rect
        guard let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw CaptureError.failed
        }
        return image
    }
}
