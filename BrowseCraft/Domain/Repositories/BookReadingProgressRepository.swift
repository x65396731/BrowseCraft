import Foundation

// 中文注释：BookReadingProgressRepository 每本书每个用户只保留一条续读位置。
protocol BookReadingProgressRepository: Sendable {
    func fetchProgress(bookID: UUID, userID: String) throws -> BookReadingProgress?
    func saveProgress(_ progress: BookReadingProgress) throws
}
