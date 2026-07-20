import SwiftUI

/// Состояние онбординга разрешений. Опрашивает PermissionsService и даёт кнопки.
@MainActor
final class OnboardingViewModel: ObservableObject {
    struct Row: Identifiable {
        let id = UUID()
        let kind: PermissionsService.Kind
        var status: PermissionsService.Status
    }

    @Published var rows: [Row] = []

    private let permissions: PermissionsService
    var onClose: (() -> Void)?

    init(permissions: PermissionsService) {
        self.permissions = permissions
        refresh()
    }

    func refresh() {
        rows = PermissionsService.Kind.allCases.map {
            Row(kind: $0, status: permissions.status($0))
        }
    }

    func request(_ kind: PermissionsService.Kind) {
        Task {
            await permissions.request(kind)
            refresh()
        }
    }

    func openSettings(_ kind: PermissionsService.Kind) {
        permissions.openSettings(kind)
    }

    var canContinue: Bool {
        permissions.essentialGranted
    }
}
