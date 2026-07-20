import Foundation

/// Владелец окна контекста. Единственный, кто решает, что уйдёт в LLM.
/// Изолирован в actor — к нему пишут из ASR-очереди и из vision-потока.
actor ContextManager {
    private var window = ContextWindow()

    func ingest(_ segment: TranscriptSegment) {
        window.addOrUpdate(segment)
    }

    func ingest(ocr: OCRResult) {
        window.setOCR(ocr)
    }

    func reset() {
        window.reset()
    }

    /// Снимок для сборки промпта: только финальные реплики + свежий OCR.
    /// Partial-куски сюда не берём — LLM не нужен недописанный текст.
    func snapshot() -> ContextSnapshot {
        let finals = window.segments.filter { $0.isFinal && !$0.text.isEmpty }
        return ContextSnapshot(segments: finals, ocr: window.lastOCR)
    }

    /// Для живого транскрипта в overlay: финалы + текущие partial-реплики.
    func displaySegments() -> [TranscriptSegment] {
        window.segments.filter { !$0.text.isEmpty }
    }
}

/// Иммутабельный срез контекста на момент запроса.
struct ContextSnapshot {
    let segments: [TranscriptSegment]
    let ocr: OCRResult?
}
