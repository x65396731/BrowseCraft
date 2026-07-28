import Foundation
import Security

enum KeychainAppUserIdentityStoreError: Error, Equatable {
    case invalidStoredUserID
    case unexpectedStatus(OSStatus)
}

/// 中文注释：业务 AppUser UUID 使用独立 Keychain service，不能复用匿名诊断身份或 UserDefaults。
struct KeychainAppUserIdentityStore: AppUserIdentityStoring {
    private static let account: String = "app-user-id"

    private let service: String

    init(
        service: String = "\(Bundle.main.bundleIdentifier ?? "com.xiefei.AnyPortal").business-identity"
    ) {
        self.service = service
    }

    func loadUserID() throws -> UUID? {
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
                  let value: String = String(data: data, encoding: .utf8),
                  let userID: UUID = UUID(uuidString: value) else {
                throw KeychainAppUserIdentityStoreError.invalidStoredUserID
            }
            return userID
        default:
            throw KeychainAppUserIdentityStoreError.unexpectedStatus(status)
        }
    }

    func saveUserID(_ userID: UUID) throws {
        let data: Data = Data(userID.uuidString.utf8)
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
                    throw KeychainAppUserIdentityStoreError.unexpectedStatus(retryStatus)
                }
                return
            }
            guard addStatus == errSecSuccess else {
                throw KeychainAppUserIdentityStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainAppUserIdentityStoreError.unexpectedStatus(updateStatus)
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

/// 中文注释：已经后端认证的 Portal UUID 只增不减，退出或切换中断后也不会被误判为访客。
struct KeychainPortalAppUserIdentityOriginStore: PortalAppUserIdentityOriginStoring {
    private static let account: String = "known-portal-app-user-ids"
    private static let lock: NSLock = NSLock()

    private let service: String

    init(
        service: String = "\(Bundle.main.bundleIdentifier ?? "com.xiefei.AnyPortal").business-identity"
    ) {
        self.service = service
    }

    func containsPortalUserID(_ userID: UUID) throws -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try self.loadPortalUserIDs().contains(userID)
    }

    func markPortalUserID(_ userID: UUID) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var userIDs: Set<UUID> = try self.loadPortalUserIDs()
        guard userIDs.insert(userID).inserted else {
            return
        }
        try self.savePortalUserIDs(userIDs)
    }

    private func loadPortalUserIDs() throws -> Set<UUID> {
        var query: [String: Any] = self.baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecItemNotFound:
            return []
        case errSecSuccess:
            guard let data: Data = item as? Data,
                  let userIDs: Set<UUID> = try? JSONDecoder().decode(
                    Set<UUID>.self,
                    from: data
                  ) else {
                throw KeychainAppUserIdentityStoreError.invalidStoredUserID
            }
            return userIDs
        default:
            throw KeychainAppUserIdentityStoreError.unexpectedStatus(status)
        }
    }

    private func savePortalUserIDs(_ userIDs: Set<UUID>) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(userIDs)
        } catch {
            throw KeychainAppUserIdentityStoreError.invalidStoredUserID
        }
        let attributes: [String: Any] = [kSecValueData as String: data]
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
            guard addStatus == errSecSuccess else {
                throw KeychainAppUserIdentityStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainAppUserIdentityStoreError.unexpectedStatus(updateStatus)
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
