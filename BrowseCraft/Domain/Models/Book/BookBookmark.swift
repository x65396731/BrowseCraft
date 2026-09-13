import Foundation

// 中文注释：BookBookmark 是用户在一本书里手动加的书签；位置同样是不透明的 `Locator` JSON。

struct BookBookmark: Identifiable, Hashable, Sendable {
    var id: UUID
    var bookID: UUID
    var userID: String
    var locatorJSON: String
    /// 中文注释：章节标题或用户自定义标题，来自 `Locator.title`。
    var title: String?
    /// 中文注释：书签处的一小段正文（EPUB）；音频书为空。
    var snippet: String?
    var createdAt: Date
}
