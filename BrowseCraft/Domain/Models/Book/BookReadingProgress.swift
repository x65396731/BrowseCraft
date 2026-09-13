import Foundation

// 中文注释：BookReadingProgress 是一本书的续读位置。位置是 Readium `Locator` 的 JSON 字符串，
// Domain 不解释它——Domain 与 Application 不依赖 Readium，只有 Infrastructure 与 Features 会还原它。

struct BookReadingProgress: Hashable, Sendable {
    var bookID: UUID
    var userID: String
    var locatorJSON: String
    /// 中文注释：Readium `Locator.locations.totalProgression`（0…1），只用于书架上的进度条；缺失时不显示。
    var totalProgression: Double?
    var updatedAt: Date
}
