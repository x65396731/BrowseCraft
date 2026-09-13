import CryptoKit
import Foundation

// 中文注释：站点书没有 LocalBook 行，进度与书签的作品标识由 sourceID + 作品地址派生成固定 UUID（设计第六节第 3 条）。
// 同一用户同一来源同一作品永远得到同一个 id；换来源 id 不同（同一本书在两个站是两份进度，与漫画历史按 sourceID 分账一致）。

enum SiteBookIdentity {
    static func bookID(sourceID: String, detailURL: String) -> UUID {
        let digest: SHA256.Digest = SHA256.hash(data: Data("site-book|\(sourceID)|\(detailURL)".utf8))
        var bytes: [UInt8] = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
