import Foundation
import Security

/// Единственная точка доступа к секретам. Ключ живёт в Keychain,
/// в код/логи/промпты/UI не попадает.
protocol SecureStore {
    func setSecret(_ value: String, for key: SecretKey) throws
    func secret(for key: SecretKey) throws -> String?
    func removeSecret(for key: SecretKey) throws
}

enum SecretKey: String {
    case llmAPIKey = "llm.api.key"
}

enum SecureStoreError: Error {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}

/// Обёртка над Keychain. Ничего не кеширует в памяти дольше вызова.
final class KeychainSecureStore: SecureStore {
    private let service: String

    init(service: String = "com.assistant.app.secrets") {
        self.service = service
    }

    func setSecret(_ value: String, for key: SecretKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecureStoreError.encodingFailed
        }
        // сначала пробуем обновить, если записи нет — добавляем
        let query = baseQuery(key)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecureStoreError.unexpectedStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    func secret(for key: SecretKey) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecureStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func removeSecret(for key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(_ key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
