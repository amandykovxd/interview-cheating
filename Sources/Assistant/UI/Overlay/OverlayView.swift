import SwiftUI

/// Содержимое overlay. Прозрачный фон, читаемый текст ответа.
struct OverlayView: View {
    @ObservedObject var model: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow
            Divider().opacity(0.3)
            ScrollView {
                Text(displayText)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        // интерактив включаем только под курсором — иначе клики идут сквозь окно
        .onHover { hovering in
            (NSApp.keyWindow ?? overlayWindow())?.ignoresMouseEvents = !hovering
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var displayText: String {
        switch model.status {
        case .error(let msg): return msg
        case .idle where model.answer.isEmpty: return model.lastTranscript
        default: return model.answer
        }
    }

    private var statusText: String {
        switch model.status {
        case .idle: return "готов"
        case .listening: return "слушаю"
        case .thinking: return "думаю"
        case .answering: return "отвечаю"
        case .error: return "ошибка"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .idle: return .green
        case .listening: return .blue
        case .thinking, .answering: return .orange
        case .error: return .red
        }
    }

    private func overlayWindow() -> NSWindow? {
        NSApp.windows.first { $0 is OverlayWindow }
    }
}
