import Foundation
import BrowseCraftCore

protocol ProtectedResourceDecrypting {
    func sha512(_ data: Data) -> Data

    func decrypt(
        ciphertext: Data,
        rule: ProtectedResourceDecryptRule,
        key: Data,
        iv: Data?
    ) throws -> Data
}
