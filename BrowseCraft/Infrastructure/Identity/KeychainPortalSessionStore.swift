import Foundation
import Security

enum KeychainPortalSessionStoreError: Error, Equatable {
    case invalidStoredSession
    case unsupportedSchemaVersion(Int)
    case unexpectedStatus(OSStatus)
}

/// 中文注释：Portal Token 与认证状态整体保存，禁止拆成多个可能只更新一半的 Keychain item。
struct KeychainPortalSessionStore: PortalSessionStoring {
    private static let account: String = "portal-session"

    private let service: String

    init(
        service: String = "\(Bundle.main.bundleIdentifier ?? "com.xiefei.AnyPortal").business-session"
    ) {
        self.service = service
    }

    func load() throws -> PortalSessionPersistence? {
        var query: [String: Any] = self.baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            guard let data: Data = item as? Data,
                  let session: PortalSessionPersistence = try? JSONDecoder().decode(
                      PortalSessionPersistence.self,
                      from: data
                  ) else {
                throw KeychainPortalSessionStoreError.invalidStoredSession
            }
            guard session.schemaVersion == PortalSessionPersistence.currentSchemaVersion else {
                throw KeychainPortalSessionStoreError.unsupportedSchemaVersion(
                    session.schemaVersion
                )
            }
            return session
        default:
            throw KeychainPortalSessionStoreError.unexpectedStatus(status)
        }
    }

    func save(_ session: PortalSessionPersistence) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw KeychainPortalSessionStoreError.invalidStoredSession
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus: OSStatus = SecItemUpdate(
            self.baseQuery as CFDictionary,
            attributes as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item: [String: Any] = self.baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus: OSStatus = SecItemAdd(item as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                let retryStatus: OSStatus = SecItemUpdate(
                    self.baseQuery as CFDictionary,
                    attributes as CFDictionary
                )
                guard retryStatus == errSecSuccess else {
                    throw KeychainPortalSessionStoreError.unexpectedStatus(retryStatus)
                }
                return
            }
            guard addStatus == errSecSuccess else {
                throw KeychainPortalSessionStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainPortalSessionStoreError.unexpectedStatus(updateStatus)
        }
    }

    func clear() throws {
        let status: OSStatus = SecItemDelete(self.baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainPortalSessionStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: Self.account
        ]
    }
}
