import Foundation
import BrowseCraftCore

public protocol ProtectedResourceDecrypting: Sendable {
    func sha512(_ data: Data) -> Data

    func decrypt(
        ciphertext: Data,
        rule: ProtectedResourceDecryptRule,
        key: Data,
        iv: Data?
    ) throws -> Data
}
