import CoreGraphics
import Foundation

/// Фасад vision-части: снять область -> распознать. С debounce, чтобы частые
/// нажатия хоткея не запускали OCR пачками.
final class VisionPipeline {
    private let capturer: ScreenRegionCapturer
    private let ocr: OCRService
    private var lastRun: Date = .distantPast
    private let debounce: TimeInterval = 0.4

    init(capturer: ScreenRegionCapturer = .init(), ocr: OCRService = .init()) {
        self.capturer = capturer
        self.ocr = ocr
    }

    /// Возвращает распознанный текст области или nil, если сработал debounce.
    func recognizeRegion(_ rect: CGRect) async -> OCRResult? {
        let now = Date()
        guard now.timeIntervalSince(lastRun) > debounce else {
            Log.vision.debug("OCR debounced")
            return nil
        }
        lastRun = now

        do {
            let image = try capturer.capture(rect: rect)
            let result = try await ocr.recognize(image)
            Log.vision.info("OCR done, lines=\(result.lines.count)")
            return result
        } catch {
            Log.vision.error("OCR failed: \(error.localizedDescription)")
            return nil
        }
    }
}
