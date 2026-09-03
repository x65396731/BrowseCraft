import Foundation
import BrowseCraftCore

public protocol ResourcePipelineCryptography: Sendable {
    func hash(_ data: Data, algorithm: ResourceHashAlgorithm) throws -> Data

    func decrypt(
        _ ciphertext: Data,
        algorithm: ResourceCipherAlgorithm,
        mode: ResourceCipherMode,
        padding: ResourceCipherPadding,
        key: Data,
        iv: Data
    ) throws -> Data
}
