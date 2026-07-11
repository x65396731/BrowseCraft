import Foundation
import Security

// 中文注释：DiagnosticIdentityStore 负责维护匿名诊断身份，避免业务代码直接读写 Keychain。

struct DiagnosticIdentity {
    let supportUserId: String
    let diagnosticCode: String
    let sessionId: String
}

final class DiagnosticIdentityStore {
    static let shared: DiagnosticIdentityStore = DiagnosticIdentityStore()

    private enum Key {
        static let supportUserId: String = "diagnostics.supportUserId"
        static let diagnosticCode: String = "diagnostics.diagnosticCode"
    }

    private let keychain: DiagnosticKeychainStore
    private let fallbackDefaults: UserDefaults
    private let sessionId: String

    private init(
        keychain: DiagnosticKeychainStore = DiagnosticKeychainStore(),
        fallbackDefaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.fallbackDefaults = fallbackDefaults
        self.sessionId = UUID().uuidString
    }

    var identity: DiagnosticIdentity {
        let supportUserId: String = self.stableValue(
            key: Key.supportUserId,
            makeValue: {
                return UUID().uuidString
            }
        )
        let diagnosticCode: String = self.stableValue(
            key: Key.diagnosticCode,
            makeValue: Self.makeDiagnosticCode
        )

        return DiagnosticIdentity(
            supportUserId: supportUserId,
            diagnosticCode: diagnosticCode,
            sessionId: self.sessionId
        )
    }

    private func stableValue(key: String, makeValue: () -> String) -> String {
        if let keychainValue: String = self.keychain.string(forKey: key), keychainValue.isEmpty == false {
            return keychainValue
        }

        if let fallbackValue: String = self.fallbackDefaults.string(forKey: key), fallbackValue.isEmpty == false {
            _ = self.keychain.set(fallbackValue, forKey: key)
            return fallbackValue
        }

        let value: String = makeValue()
        if self.keychain.set(value, forKey: key) == false {
            self.fallbackDefaults.set(value, forKey: key)
        }
        return value
    }

    private static func makeDiagnosticCode() -> String {
        let alphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let firstGroup: String = Self.makeCodeGroup(length: 4, alphabet: alphabet)
        let secondGroup: String = Self.makeCodeGroup(length: 4, alphabet: alphabet)
        return "BC-\(firstGroup)-\(secondGroup)"
    }

    private static func makeCodeGroup(length: Int, alphabet: [Character]) -> String {
        var result: String = ""
        for _ in 0..<length {
            if let character: Character = alphabet.randomElement() {
                result.append(character)
            }
        }
        return result
    }
}

struct DiagnosticKeychainStore {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.xiefei.AnyPortal") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query: [String: Any] = self.baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data: Data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, forKey key: String) -> Bool {
        let data: Data = Data(value.utf8)
        SecItemDelete(self.baseQuery(forKey: key) as CFDictionary)

        var query: [String: Any] = self.baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: key
        ]
    }
}
