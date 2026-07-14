import Foundation
import SwiftUI

/// Состояние overlay. Только отображение, никакой бизнес-логики.
/// Обновляется координатором на main.
@MainActor
final class OverlayViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case listening
        case thinking
        case answering
        case error(String)
    }

    @Published var status: Status = .idle
    @Published var answer: String = ""
    @Published var lastTranscript: String = ""

    // Батчим обновление ответа, чтобы не перерисовывать на каждый токен.
    private var pendingAnswer: String = ""
    private var flushTask: Task<Void, Never>?

    func beginAnswer() {
        answer = ""
        pendingAnswer = ""
        status = .answering
    }

    func appendDelta(_ delta: String) {
        pendingAnswer += delta
        scheduleFlush()
    }

    func finishAnswer() {
        flushTask?.cancel()
        answer = pendingAnswer
        status = .idle
    }

    func showError(_ message: String) {
        status = .error(message)
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            // раз в ~50 мс переносим накопленное в published-поле
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self else { return }
            self.answer = self.pendingAnswer
            self.flushTask = nil
        }
    }
}
