import AppKit
import SwiftUI

/// Окно просмотра истории (расшифрованной). Только чтение.
@MainActor
final class HistoryWindowController {
    private var window: NSWindow?
    private let store: SessionStore

    init(store: SessionStore) {
        self.store = store
    }

    func show() {
        let model = HistoryViewModel(store: store)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = "История сессий"
        win.titlebarAppearsTransparent = true
        win.center()
        win.contentView = NSHostingView(rootView: HistoryView(model: model))
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        model.load()
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var sessions: [SavedSession] = []
    private let store: SessionStore

    init(store: SessionStore) { self.store = store }

    func load() {
        Task {
            let loaded = (try? await store.loadAll()) ?? []
            self.sessions = loaded
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel

    var body: some View {
        if model.sessions.isEmpty {
            Text("История пуста").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.sessions) { session in
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(session.exchanges.enumerated()), id: \.offset) { _, ex in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("В: \(ex.question)").font(.system(size: 12, weight: .medium))
                            Text("О: \(ex.answer)").font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
