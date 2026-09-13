import Foundation
import Observation

// 中文注释：BookShelfViewModel 负责书架：列本地书、从「文件」导入、删除。不碰 Readium。

@MainActor
@Observable
final class BookShelfViewModel {
    private(set) var items: [LocalBookShelfItem] = []
    private(set) var isImporting: Bool = false
    var errorMessage: String?

    private let listUseCase: ListLocalBooksUseCase
    private let importUseCase: ImportLocalBookUseCase
    private let deleteUseCase: DeleteLocalBookUseCase
    private let fileStore: any BookFileStoring
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let fallbackUserID: String

    init(
        listUseCase: ListLocalBooksUseCase,
        importUseCase: ImportLocalBookUseCase,
        deleteUseCase: DeleteLocalBookUseCase,
        fileStore: any BookFileStoring,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        userID: String = AppUser.localDefaultID
    ) {
        self.listUseCase = listUseCase
        self.importUseCase = importUseCase
        self.deleteUseCase = deleteUseCase
        self.fileStore = fileStore
        self.activeAppUser = activeAppUser
        self.fallbackUserID = userID
    }

    var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? self.fallbackUserID
    }

    func load() {
        do {
            self.items = try self.listUseCase.execute(userID: self.currentUserID)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 中文注释：逐个导入；一个失败不影响其余，失败原因汇总到 errorMessage。
    func importBooks(from urls: [URL]) async {
        guard urls.isEmpty == false else {
            return
        }
        self.isImporting = true
        defer { self.isImporting = false }
        var failures: [String] = []
        for url: URL in urls {
            do {
                _ = try await self.importUseCase.execute(sourceURL: url, userID: self.currentUserID)
            } catch let error as LocalBookImportError {
                failures.append("\(url.lastPathComponent): \(Self.message(for: error))")
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        self.load()
        if failures.isEmpty == false {
            self.errorMessage = failures.joined(separator: "\n")
        }
    }

    func delete(_ book: LocalBook) async {
        do {
            try await self.deleteUseCase.execute(bookID: book.id, userID: self.currentUserID)
            self.load()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func coverURL(for book: LocalBook) -> URL? {
        return book.coverRelativePath.map { self.fileStore.fileURL(relativePath: $0) }
    }

    static func message(for error: LocalBookImportError) -> String {
        switch error {
        case .unsupportedFormat:
            return NSLocalizedString("Unsupported file", comment: "本地书导入：不支持的文件")
        case .protectedPublication:
            return NSLocalizedString("Protected book", comment: "本地书导入：受保护的书籍")
        case .openFailed(let reason):
            return NSLocalizedString("Open failed", comment: "本地书导入：打开失败") + " (\(reason))"
        }
    }
}
