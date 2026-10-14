import Foundation
import Security

/// 中文注释：Apple user 标识与业务身份同一个 Keychain service、不同 account；仅本机、首次解锁后可读。
struct KeychainAppleUserIdentifierStore: AppleUserIdentifierStoring {
    private static let account: String = "apple-user-identifier"

    private let service: String

    init(
        service: String = "\(Bundle.main.bundleIdentifier ?? "com.xiefei.AnyPortal").business-identity"
    ) {
        self.service = service
    }

    func loadUserIdentifier() throws -> String? {
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
                  value.isEmpty == false else {
                throw KeychainAppUserIdentityStoreError.invalidStoredUserID
            }
            return value
        default:
            throw KeychainAppUserIdentityStoreError.unexpectedStatus(status)
        }
    }

    func saveUserIdentifier(_ userIdentifier: String) throws {
        let data: Data = Data(userIdentifier.utf8)
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

    func clearUserIdentifier() throws {
        let status: OSStatus = SecItemDelete(self.baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainAppUserIdentityStoreError.unexpectedStatus(status)
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
