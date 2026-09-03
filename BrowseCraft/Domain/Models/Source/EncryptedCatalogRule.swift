import Foundation

/// 中文注释：Catalog 下发的加密规则载荷；解密由 Application 的 CatalogRuleDecryptor 负责。
struct EncryptedCatalogRule: Decodable, Hashable, Sendable {
    let version: Int
    let keyId: String
    let nonce: String
    let ciphertext: String
}
