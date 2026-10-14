import Foundation
import Security

/// 中文注释：Apple user 标识与业务身份同一个 Keychain service、不同 account；仅本机、首次解锁后可读。
/// 值写成「标识|保存时的 Unix 秒|这次授权后是否见过 authorized（0/1）」（删除账号设计第十节）；缺后两段的旧值照样能读，按没见过处理。
struct KeychainAppleUserIdentifierStore: AppleUserIdentifierStoring {
    private static let account: String = "apple-user-identifier"
    private static let separator: Character = "|"

    private let service: String
    private let now: @Sendable () -> Date

    init(
        service: String = "\(Bundle.main.bundleIdentifier ?? "com.xiefei.AnyPortal").business-identity",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.now = now
    }

    private struct StoredValue {
        var identifier: String
        var savedAtSeconds: Int?
        var hasObservedAuthorized: Bool

        var encoded: String {
            return [
                self.identifier,
                self.savedAtSeconds.map(String.init) ?? "",
                self.hasObservedAuthorized ? "1" : "0"
            ].joined(separator: String(KeychainAppleUserIdentifierStore.separator))
        }
    }

    func loadUserIdentifier() throws -> String? {
        return try self.loadStoredValue()?.identifier
    }

    func lastAuthorizedAt() throws -> Date? {
        return try self.loadStoredValue()?.savedAtSeconds
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    func hasObservedAuthorized() throws -> Bool {
        return try self.loadStoredValue()?.hasObservedAuthorized ?? false
    }

    func markObservedAuthorized() throws {
        guard var value: StoredValue = try self.loadStoredValue(),
              value.hasObservedAuthorized == false else {
            return
        }
        value.hasObservedAuthorized = true
        try self.writeRawValue(value.encoded)
    }

    private func loadStoredValue() throws -> StoredValue? {
        guard let raw: String = try self.loadRawValue() else {
            return nil
        }
        let parts: [Substring] = raw.split(
            separator: Self.separator,
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        guard let identifier: Substring = parts.first, identifier.isEmpty == false else {
            throw KeychainAppUserIdentityStoreError.invalidStoredUserID
        }
        return StoredValue(
            identifier: String(identifier),
            savedAtSeconds: parts.count >= 2 ? Int(parts[1]) : nil,
            hasObservedAuthorized: parts.count >= 3 && parts[2] == "1"
        )
    }

    private func loadRawValue() throws -> String? {
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
        let value: StoredValue = StoredValue(
            identifier: userIdentifier,
            savedAtSeconds: Int(self.now().timeIntervalSince1970),
            hasObservedAuthorized: false
        )
        try self.writeRawValue(value.encoded)
    }

    private func writeRawValue(_ raw: String) throws {
        let data: Data = Data(raw.utf8)
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
