import SwiftUI

/// Экран выдачи разрешений при первом запуске.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Доступы").font(.title2.bold())
                Text("Ассистент работает локально. Дайте нужные разрешения — их можно "
                     + "поменять позже в системных настройках.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            ForEach(model.rows) { row in
                permissionRow(row)
            }

            Text("Системный звук (речь собеседника) запрашивается при первом "
                 + "включении «Слушать».")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Готово") { model.onClose?() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()   // вернулись из системных настроек — обновим статусы
        }
    }

    private func permissionRow(_ row: OnboardingViewModel.Row) -> some View {
        HStack(spacing: 12) {
            statusDot(row.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.kind.title).font(.system(size: 13, weight: .medium))
                Text("Нужно, чтобы \(row.kind.reason).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if row.status == .granted {
                Text("выдано").font(.system(size: 11)).foregroundStyle(.green)
            } else {
                Button("Разрешить") { model.request(row.kind) }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statusDot(_ status: PermissionsService.Status) -> some View {
        Circle()
            .fill(status == .granted ? Color.green : .orange)
            .frame(width: 9, height: 9)
    }
}
