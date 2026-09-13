import Foundation

// 中文注释：ImportLocalBookUseCase：嗅探 → 复制进容器 → 打开一次取元数据与封面 → 落库。
// 复制之后任一步失败都把已复制的文件删掉；同一文件（内容哈希相同）再次导入直接返回已有的书。

enum LocalBookImportError: Error, Equatable, Sendable {
    case unsupportedFormat
    case protectedPublication
    case openFailed(reason: String)
}

struct ImportLocalBookUseCase: Sendable {
    private let inspector: any BookFileInspecting
    private let fileStore: any BookFileStoring
    private let opener: any BookPublicationOpening
    private let repository: any LocalBookRepository
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    init(
        inspector: any BookFileInspecting,
        fileStore: any BookFileStoring,
        opener: any BookPublicationOpening,
        repository: any LocalBookRepository,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.inspector = inspector
        self.fileStore = fileStore
        self.opener = opener
        self.repository = repository
        self.now = now
        self.makeID = makeID
    }

    func execute(sourceURL: URL, userID: String) async throws -> LocalBook {
        guard case .supported(let format, let fileExtension) = try await self.inspector.inspect(fileURL: sourceURL) else {
            throw LocalBookImportError.unsupportedFormat
        }

        let bookID: UUID = self.makeID()
        let stored: StoredBookFile = try await self.fileStore.storeBookFile(
            from: sourceURL,
            bookID: bookID,
            fileExtension: fileExtension
        )

        if let existing: LocalBook = try self.repository.fetchBook(fileSHA256: stored.sha256, userID: userID) {
            try await self.fileStore.removeFile(relativePath: stored.relativePath)
            return existing
        }

        do {
            let handle: any BookPublicationHandle = try await self.opener.openPublication(
                fileURL: self.fileStore.fileURL(relativePath: stored.relativePath),
                format: format
            )
            let metadata: BookPublicationMetadata = handle.metadata
            if metadata.isRestricted {
                throw LocalBookImportError.protectedPublication
            }
            var coverRelativePath: String? = nil
            if let coverData: Data = metadata.coverImageData, coverData.isEmpty == false {
                coverRelativePath = try await self.fileStore.storeCover(coverData, bookID: bookID)
            }
            let book: LocalBook = LocalBook(
                id: bookID,
                userID: userID,
                title: Self.title(from: metadata, sourceURL: sourceURL),
                author: metadata.author,
                format: format,
                fileRelativePath: stored.relativePath,
                coverRelativePath: coverRelativePath,
                fileSHA256: stored.sha256,
                byteCount: stored.byteCount,
                importedAt: self.now(),
                lastOpenedAt: nil
            )
            try self.repository.saveBook(book)
            return book
        } catch let error as LocalBookImportError {
            try? await self.fileStore.removeFile(relativePath: stored.relativePath)
            throw error
        } catch let error as BookPublicationOpenError {
            try? await self.fileStore.removeFile(relativePath: stored.relativePath)
            switch error {
            case .protectedPublication:
                throw LocalBookImportError.protectedPublication
            case .unsupportedFormat:
                throw LocalBookImportError.unsupportedFormat
            case .fileMissing:
                throw LocalBookImportError.openFailed(reason: "file-missing")
            case .parsingFailed(let reason):
                throw LocalBookImportError.openFailed(reason: reason)
            }
        } catch {
            try? await self.fileStore.removeFile(relativePath: stored.relativePath)
            throw error
        }
    }

    /// 中文注释：出版物没有标题时退回文件名（去扩展名），不留空标题。
    private static func title(from metadata: BookPublicationMetadata, sourceURL: URL) -> String {
        let trimmed: String = (metadata.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return trimmed
        }
        return sourceURL.deletingPathExtension().lastPathComponent
    }
}
