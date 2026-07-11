import CryptoKit
import Foundation

enum CatalogRuleDecryptionError: LocalizedError {
    case unsupportedVersion(Int)
    case missingKey(String)
    case invalidBase64(String)
    case invalidCiphertext
    case decryptionFailed
    case invalidPlaintext

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Unsupported catalog rule encryption version: \(version)."
        case .missingKey(let keyID):
            return "Missing catalog rule decryption key: \(keyID)."
        case .invalidBase64(let field):
            return "Invalid catalog rule encrypted field: \(field)."
        case .invalidCiphertext:
            return "Invalid catalog rule ciphertext."
        case .decryptionFailed:
            return "Failed to decrypt catalog rule."
        case .invalidPlaintext:
            return "Invalid decrypted catalog rule payload."
        }
    }
}

struct EncryptedCatalogRule: Decodable {
    let version: Int
    let keyId: String
    let nonce: String
    let ciphertext: String
}

protocol CatalogRuleDecryptionKeyProviding {
    func key(for keyID: String) -> SymmetricKey?
}

struct CatalogRuleDecryptionKeyProvider: CatalogRuleDecryptionKeyProviding {
    private let keysByID: [String: SymmetricKey]

    init(keysByID: [String: SymmetricKey]) {
        self.keysByID = keysByID
    }

    func key(for keyID: String) -> SymmetricKey? {
        return self.keysByID[keyID]
    }
}

struct BundleCatalogRuleDecryptionKeyProvider: CatalogRuleDecryptionKeyProviding {
    private let bundle: Bundle
    private let environment: [String: String]

    init(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.bundle = bundle
        self.environment = environment
    }

    func key(for keyID: String) -> SymmetricKey? {
        return self.keysByID()[keyID]
    }

    private func keysByID() -> [String: SymmetricKey] {
        let environmentValue: String = self.environment["BROWSECRAFT_CATALOG_ENCRYPTION_KEYS"] ?? ""
        let configuredValue: String = environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? self.infoString(forKey: "BrowseCraftCatalogEncryptionKeys")
            : environmentValue
        return Self.keys(from: configuredValue)
    }

    private func infoString(forKey key: String) -> String {
        return (self.bundle.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    private static func keys(from configuredValue: String) -> [String: SymmetricKey] {
        let pairs: [String] = configuredValue
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        var keysByID: [String: SymmetricKey] = [:]

        for pair in pairs {
            let components: [Substring] = pair.split(separator: "=", maxSplits: 1)
            guard components.count == 2 else {
                continue
            }

            let keyID: String = String(components[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let encodedKey: String = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard keyID.isEmpty == false,
                  let keyData: Data = Self.base64Data(from: encodedKey),
                  keyData.count == 32 else {
                continue
            }

            keysByID[keyID] = SymmetricKey(data: keyData)
        }

        return keysByID
    }

    private static func base64Data(from value: String) -> Data? {
        let base64Value: String = value.hasPrefix("base64:")
            ? String(value.dropFirst("base64:".count))
            : value
        return Data(base64Encoded: base64Value)
    }
}

struct CatalogRuleDecryptor {
    private let keyProvider: CatalogRuleDecryptionKeyProviding
    private let jsonDecoder: JSONDecoder

    init(
        keyProvider: CatalogRuleDecryptionKeyProviding = BundleCatalogRuleDecryptionKeyProvider(),
        jsonDecoder: JSONDecoder = JSONDecoder()
    ) {
        self.keyProvider = keyProvider
        self.jsonDecoder = jsonDecoder
    }

    func decrypt(_ encryptedRule: EncryptedCatalogRule) throws -> CatalogRuleJSONValue {
        guard encryptedRule.version == 1 else {
            throw CatalogRuleDecryptionError.unsupportedVersion(encryptedRule.version)
        }

        guard let key: SymmetricKey = self.keyProvider.key(for: encryptedRule.keyId) else {
            throw CatalogRuleDecryptionError.missingKey(encryptedRule.keyId)
        }

        guard let nonceData: Data = Data(base64Encoded: encryptedRule.nonce) else {
            throw CatalogRuleDecryptionError.invalidBase64("nonce")
        }
        guard let sealedData: Data = Data(base64Encoded: encryptedRule.ciphertext) else {
            throw CatalogRuleDecryptionError.invalidBase64("ciphertext")
        }
        guard sealedData.count >= 16 else {
            throw CatalogRuleDecryptionError.invalidCiphertext
        }

        let ciphertext: Data = sealedData.prefix(sealedData.count - 16)
        let tag: Data = sealedData.suffix(16)

        do {
            let nonce: AES.GCM.Nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox: AES.GCM.SealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertext,
                tag: tag
            )
            let plaintext: Data = try AES.GCM.open(sealedBox, using: key)
            return try self.jsonDecoder.decode(CatalogRuleJSONValue.self, from: plaintext)
        } catch is DecodingError {
            throw CatalogRuleDecryptionError.invalidPlaintext
        } catch {
            throw CatalogRuleDecryptionError.decryptionFailed
        }
    }
}

enum CatalogRuleJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: CatalogRuleJSONValue])
    case array([CatalogRuleJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value: Bool = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value: Int = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value: Double = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value: String = try? container.decode(String.self) {
            self = .string(value)
        } else if let value: [String: CatalogRuleJSONValue] = try? container.decode([String: CatalogRuleJSONValue].self) {
            self = .object(value)
        } else if let value: [CatalogRuleJSONValue] = try? container.decode([CatalogRuleJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container: SingleValueEncodingContainer = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container: SingleValueEncodingContainer = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container: SingleValueEncodingContainer = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let value):
            var container: KeyedEncodingContainer<CatalogRuleDynamicCodingKey> = encoder.container(
                keyedBy: CatalogRuleDynamicCodingKey.self
            )
            for (key, nestedValue) in value {
                try container.encode(nestedValue, forKey: CatalogRuleDynamicCodingKey(stringValue: key))
            }
        case .array(let value):
            var container: UnkeyedEncodingContainer = encoder.unkeyedContainer()
            for element in value {
                try container.encode(element)
            }
        case .null:
            var container: SingleValueEncodingContainer = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    var importRuleJSON: CatalogRuleJSONValue {
        guard case .object(let object) = self,
              let nestedRuleJSON: CatalogRuleJSONValue = object["ruleJSON"] else {
            return self
        }

        return nestedRuleJSON
    }
}

private struct CatalogRuleDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
