import Foundation

// 中文注释：BookReadingProgressRepository 每本书每个用户只保留一条续读位置。
protocol BookReadingProgressRepository: Sendable {
    func fetchProgress(bookID: UUID, userID: String) throws -> BookReadingProgress?
    func saveProgress(_ progress: BookReadingProgress) throws
    /// 中文注释：v4 起进度不再外键级联到 local_books（站点书没有那一行），删书时显式删。
    func deleteProgress(bookID: UUID, userID: String) throws
}
