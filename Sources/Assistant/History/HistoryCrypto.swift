import CryptoKit
import Foundation

/// Симметричное шифрование истории. AES-GCM: и конфиденциальность, и целостность.
/// Ключ живёт в Keychain, здесь только операции над Data.
struct HistoryCrypto {
    private let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    func encrypt(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw CocoaError(.coderInvalidValue)
        }
        return combined
    }

    func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }
}

extension HistoryCrypto {
    /// Достаёт ключ из Keychain, при первом обращении генерит и сохраняет.
    static func withKeychainKey(_ store: SecureStore) throws -> HistoryCrypto {
        if let b64 = try store.secret(for: .historyKey),
           let raw = Data(base64Encoded: b64) {
            return HistoryCrypto(key: SymmetricKey(data: raw))
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        try store.setSecret(raw.base64EncodedString(), for: .historyKey)
        return HistoryCrypto(key: key)
    }
}
