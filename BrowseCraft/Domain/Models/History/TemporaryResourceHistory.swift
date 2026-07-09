import Foundation

enum TemporaryResourceHistoryKind: String, Codable, Hashable {
    case comic
    case video
}

enum TemporaryVideoPlaybackKind: String, Codable, Hashable {
    case webPage
    case directMedia
}

// 中文注释：TemporaryResourceHistory 保存未加入 Source DB 的临时资源访问历史。
struct TemporaryResourceHistory: Identifiable, Hashable {
    var id: String {
        return [
            self.userID,
            self.kind.rawValue,
            self.resourceURL.absoluteString
        ].joined(separator: "::")
    }

    var userID: String
    var kind: TemporaryResourceHistoryKind
    var title: String
    var resourceURL: URL
    var coverURL: URL?
    var sourcePageURL: URL?
    var matchedKeyword: String?
    var videoPlaybackKind: TemporaryVideoPlaybackKind?
    var visitedAt: Date
}
