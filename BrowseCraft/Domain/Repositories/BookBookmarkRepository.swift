import Foundation

// 中文注释：BookBookmarkRepository 负责一本书的书签列表。
protocol BookBookmarkRepository: Sendable {
    /// 中文注释：按创建时间倒序。
    func fetchBookmarks(bookID: UUID, userID: String) throws -> [BookBookmark]
    func saveBookmark(_ bookmark: BookBookmark) throws
    func deleteBookmark(id: UUID, userID: String) throws
}
