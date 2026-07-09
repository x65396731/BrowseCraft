import Foundation
import GRDB

// 中文注释：TemporaryResourceHistoryRecord 是 temporary_resource_history 表的一行。
struct TemporaryResourceHistoryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "temporary_resource_history"

    var userID: String
    var kind: String
    var title: String
    var resourceURL: String
    var coverURL: String?
    var sourcePageURL: String?
    var matchedKeyword: String?
    var videoPlaybackKind: String?
    var visitedAt: Date

    init(history: TemporaryResourceHistory) {
        self.userID = history.userID
        self.kind = history.kind.rawValue
        self.title = history.title
        self.resourceURL = history.resourceURL.absoluteString
        self.coverURL = history.coverURL?.absoluteString
        self.sourcePageURL = history.sourcePageURL?.absoluteString
        self.matchedKeyword = history.matchedKeyword
        self.videoPlaybackKind = history.videoPlaybackKind?.rawValue
        self.visitedAt = history.visitedAt
    }

    func domainModel() -> TemporaryResourceHistory? {
        guard let kind: TemporaryResourceHistoryKind = TemporaryResourceHistoryKind(rawValue: self.kind),
              let resourceURL: URL = URL(string: self.resourceURL) else {
            return nil
        }

        return TemporaryResourceHistory(
            userID: self.userID,
            kind: kind,
            title: self.title,
            resourceURL: resourceURL,
            coverURL: self.coverURL.flatMap(URL.init(string:)),
            sourcePageURL: self.sourcePageURL.flatMap(URL.init(string:)),
            matchedKeyword: self.matchedKeyword,
            videoPlaybackKind: self.videoPlaybackKind.flatMap(TemporaryVideoPlaybackKind.init(rawValue:)),
            visitedAt: self.visitedAt
        )
    }
}
