import BrowseCraftCore
import BrowseCraftDomain
import CryptoKit
import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：`BCA-RUNTIME-004` 的另一半（2026-10-10 裁定）：加密目录里单条规则解不开（密钥不认得、没带密文）逐条跳过，
// 解得开的照常进入；整表一条都解不开才整表失败。
struct LoadCatalogSourcesUndecryptableRuleTests {
    private static let catalogKey: SymmetricKey = SymmetricKey(size: .bits256)

    @Test func undecryptableEntriesAreSkippedAndTheRestDecode() async throws {
        let good: EncryptedCatalogRule = try Self.encryptedRule(keyId: "test-key", payload: ["version": 2, "name": "Good"])
        let unknownKey: EncryptedCatalogRule = try Self.encryptedRule(keyId: "rotated-key", payload: ["version": 2, "name": "Rotated"])
        let loader: RecordingCatalogDataLoader = RecordingCatalogDataLoader(
            payload: """
            [
              {"id": "c1", "name": "Good", "baseURL": "https://c/", "kind": "comic", "encryptedRule": \(Self.json(good))},
              {"id": "c2", "name": "Rotated", "baseURL": "https://r/", "kind": "comic", "encryptedRule": \(Self.json(unknownKey))},
              {"id": "c3", "name": "Plain", "baseURL": "https://p/", "kind": "comic"}
            ]
            """
        )
        let useCase: LoadCatalogSourcesUseCase = LoadCatalogSourcesUseCase(
            pageDataLoader: loader,
            catalogRuleDecryptor: Self.decryptor()
        )

        let sources: [CatalogSource] = try await useCase.execute()

        #expect(sources.map(\.id) == ["c1"])
        #expect(sources.first?.ruleJSON.contains("\"name\":\"Good\"") == true)
    }

    @Test func aCatalogWhereNothingDecryptsStillFailsAsAWhole() async throws {
        let unknownKey: EncryptedCatalogRule = try Self.encryptedRule(keyId: "rotated-key", payload: ["version": 2, "name": "Rotated"])
        let loader: RecordingCatalogDataLoader = RecordingCatalogDataLoader(
            payload: """
            [
              {"id": "c2", "name": "Rotated", "baseURL": "https://r/", "kind": "comic", "encryptedRule": \(Self.json(unknownKey))}
            ]
            """
        )
        let useCase: LoadCatalogSourcesUseCase = LoadCatalogSourcesUseCase(
            pageDataLoader: loader,
            catalogRuleDecryptor: Self.decryptor()
        )

        await #expect(throws: CatalogRuleDecryptionError.self) {
            _ = try await useCase.execute()
        }
    }

    /// 用与 PortalCore 相同的 AES-256-GCM 形态（nonce + ciphertext‖tag）封装一条 catalog payload。
    private static func encryptedRule(keyId: String, payload: [String: Any]) throws -> EncryptedCatalogRule {
        let plaintext: Data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let nonce: AES.GCM.Nonce = AES.GCM.Nonce()
        let sealed: AES.GCM.SealedBox = try AES.GCM.seal(plaintext, using: Self.catalogKey, nonce: nonce)
        return EncryptedCatalogRule(
            version: 1,
            keyId: keyId,
            nonce: Data(nonce).base64EncodedString(),
            ciphertext: (sealed.ciphertext + sealed.tag).base64EncodedString()
        )
    }

    private static func json(_ rule: EncryptedCatalogRule) -> String {
        return """
        {"version": \(rule.version), "keyId": "\(rule.keyId)", "nonce": "\(rule.nonce)", "ciphertext": "\(rule.ciphertext)"}
        """
    }

    private static func decryptor() -> CatalogRuleDecryptor {
        return CatalogRuleDecryptor(
            keyProvider: CatalogRuleDecryptionKeyProvider(keysByID: ["test-key": Self.catalogKey])
        )
    }
}

private final class RecordingCatalogDataLoader: PageDataLoader, @unchecked Sendable {
    private let payload: String

    init(payload: String) {
        self.payload = payload
    }

    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse {
        return PageDataResponse(data: Data(self.payload.utf8), finalURL: request.url)
    }
}
