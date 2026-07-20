import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Проверка и запрос системных разрешений (TCC). Ничего не кеширует —
/// статус читается системными API на каждый запрос.
@MainActor
final class PermissionsService {
    enum Kind: CaseIterable {
        case microphone        // распознавание своей речи
        case screenRecording   // OCR области экрана
        case accessibility     // глобальные горячие клавиши

        var title: String {
            switch self {
            case .microphone: return "Микрофон"
            case .screenRecording: return "Запись экрана"
            case .accessibility: return "Универсальный доступ"
            }
        }

        var reason: String {
            switch self {
            case .microphone: return "распознавать вашу речь"
            case .screenRecording: return "снимать область экрана для OCR"
            case .accessibility: return "горячие клавиши ⇧⌘A / ⇧⌘O"
            }
        }
    }

    enum Status { case granted, denied, notDetermined }

    func status(_ kind: Kind) -> Status {
        switch kind {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        }
    }

    /// Запрос разрешения. Где возможно — системный промпт, иначе ведём в настройки.
    func request(_ kind: Kind) async {
        switch kind {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .screenRecording:
            // системный промпт; если уже решено — просто откроем настройки
            if !CGRequestScreenCaptureAccess() {
                openSettings(kind)
            }
        case .accessibility:
            // промпт с добавлением в список, иначе настройки
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            if !AXIsProcessTrustedWithOptions(opts as CFDictionary) {
                openSettings(kind)
            }
        }
    }

    func openSettings(_ kind: Kind) {
        let anchor: String
        switch kind {
        case .microphone: anchor = "Privacy_Microphone"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .accessibility: anchor = "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Микрофон обязателен для основной работы; остальное — по мере надобности.
    var essentialGranted: Bool {
        status(.microphone) == .granted
    }
}
