import Foundation
import Security

enum SecretStoreError: Error, Equatable {
    case notFound
    case unexpectedStatus(OSStatus)
    case invalidData
}

protocol SecretStore: Sendable {
    func save(_ secret: String, for key: String) throws
    func read(_ key: String) throws -> String
    func delete(_ key: String) throws
}

struct KeychainSecretStore: SecretStore {
    private let service: String
    private let client: KeychainClient

    init(service: String = "com.prismos.PrismOS.secrets", client: KeychainClient = SystemKeychainClient()) {
        self.service = service
        self.client = client
    }

    func save(_ secret: String, for key: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(for: key)
        let status = client.update(query: query, attributes: [kSecValueData as String: data])
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = client.add(query: addQuery)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(addStatus)
        }
    }

    func read(_ key: String) throws -> String {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let result = client.copyMatching(query: query)
        let status = result.status
        guard status != errSecItemNotFound else {
            throw SecretStoreError.notFound
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(status)
        }
        guard let data = result.data, let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }
        return value
    }

    func delete(_ key: String) throws {
        let status = client.delete(query: baseQuery(for: key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

protocol KeychainClient: Sendable {
    func add(query: [String: Any]) -> OSStatus
    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus
    func copyMatching(query: [String: Any]) -> (status: OSStatus, data: Data?)
    func delete(query: [String: Any]) -> OSStatus
}

struct SystemKeychainClient: KeychainClient {
    func add(query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func copyMatching(query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    func delete(query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

final class FakeKeychainClient: KeychainClient, @unchecked Sendable {
    private var values: [String: Data] = [:]

    func add(query: [String: Any]) -> OSStatus {
        guard let key = key(from: query), let data = query[kSecValueData as String] as? Data else {
            return errSecParam
        }
        guard values[key] == nil else {
            return errSecDuplicateItem
        }
        values[key] = data
        return errSecSuccess
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        guard let key = key(from: query), let data = attributes[kSecValueData as String] as? Data else {
            return errSecParam
        }
        guard values[key] != nil else {
            return errSecItemNotFound
        }
        values[key] = data
        return errSecSuccess
    }

    func copyMatching(query: [String: Any]) -> (status: OSStatus, data: Data?) {
        guard let key = key(from: query) else {
            return (errSecParam, nil)
        }
        guard let data = values[key] else {
            return (errSecItemNotFound, nil)
        }
        return (errSecSuccess, data)
    }

    func delete(query: [String: Any]) -> OSStatus {
        guard let key = key(from: query) else {
            return errSecParam
        }
        values.removeValue(forKey: key)
        return errSecSuccess
    }

    private func key(from query: [String: Any]) -> String? {
        guard let service = query[kSecAttrService as String] as? String,
              let account = query[kSecAttrAccount as String] as? String else {
            return nil
        }
        return "\(service):\(account)"
    }
}

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]

    func save(_ secret: String, for key: String) throws {
        values[key] = secret
    }

    func read(_ key: String) throws -> String {
        guard let value = values[key] else {
            throw SecretStoreError.notFound
        }
        return value
    }

    func delete(_ key: String) throws {
        values.removeValue(forKey: key)
    }
}
