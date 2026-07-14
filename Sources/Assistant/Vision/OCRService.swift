import CoreGraphics
import Foundation
import Vision

/// OCR через Vision. Запускается только по событию (хоткей), не постоянно.
/// Тяжёлый perform идёт вне main. Кэш по хешу кадра гасит повторные запросы.
final class OCRService {
    private var lastHash: Int?
    private var lastResult: OCRResult?

    func recognize(_ image: CGImage) async throws -> OCRResult {
        // если кадр не менялся — отдаём кэш, OCR не гоняем
        let hash = Self.perceptualHash(image)
        if hash == lastHash, let cached = lastResult {
            Log.vision.debug("OCR cache hit")
            return cached
        }

        let result = try await Task.detached(priority: .userInitiated) {
            try Self.performOCR(image)
        }.value

        lastHash = hash
        lastResult = result
        return result
    }

    private static func performOCR(_ image: CGImage) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ru", "en"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let lines: [OCRResult.Line] = (request.results ?? []).compactMap { obs in
            guard let top = obs.topCandidates(1).first else { return nil }
            return OCRResult.Line(text: top.string, confidence: top.confidence)
        }
        return OCRResult(lines: lines, capturedAt: Date())
    }

    /// Грубый хеш: даунскейл до 8x8 grayscale и суммарная яркость по ячейкам.
    /// Нужен только чтобы отличить "тот же кадр" от "другого", не для точности.
    private static func perceptualHash(_ image: CGImage) -> Int {
        let side = 8
        let bytesPerRow = side
        var pixels = [UInt8](repeating: 0, count: side * side)
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &pixels,
            width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image.width ^ image.height }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var hash = 0
        for (i, p) in pixels.enumerated() {
            if p > 127 { hash |= (1 << (i % 63)) }
        }
        return hash
    }
}
