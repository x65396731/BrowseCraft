import CryptoKit
import Foundation

/// 中文注释：只返回不可逆 scope hash；调用方不得持久化或记录原始 CloudKit user record name。
struct CloudAccountScopeDeriver: Sendable {
    func derive(containerIdentifier: String, userRecordName: String) -> CloudAccountScope {
        let material: String = "\(containerIdentifier.utf8.count):\(containerIdentifier)" +
            "\(userRecordName.utf8.count):\(userRecordName)"
        let digest: SHA256.Digest = SHA256.hash(data: Data(material.utf8))
        let hash: String = digest.map { byte in
            String(format: "%02x", byte)
        }.joined()
        return .cloud(hash: hash)
    }
}
