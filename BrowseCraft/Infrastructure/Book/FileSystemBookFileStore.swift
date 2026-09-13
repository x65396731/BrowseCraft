import CryptoKit
import Foundation

// 中文注释：FileSystemBookFileStore 把导入的书复制进 Application Support/BrowseCraft/Books；文件名是书的 UUID。
// 安全作用域访问在这里开关；相对路径只是文件名，绝对路径由 rootDirectory 拼出。

enum BookFileStoreError: Error, Equatable, Sendable {
    case sourceUnreadable
}

final class FileSystemBookFileStore: BookFileStoring, @unchecked Sendable {
    private let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    /// 中文注释：与 AppDatabase 同一个 Application Support/BrowseCraft 目录下的 Books 子目录。
    static func makeDefault(fileManager: FileManager = .default) throws -> FileSystemBookFileStore {
        let appSupportDirectory: URL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let booksDirectory: URL = appSupportDirectory
            .appendingPathComponent("BrowseCraft", isDirectory: true)
            .appendingPathComponent("Books", isDirectory: true)
        return FileSystemBookFileStore(rootDirectory: booksDirectory, fileManager: fileManager)
    }

    func storeBookFile(from sourceURL: URL, bookID: UUID, fileExtension: String) async throws -> StoredBookFile {
        try self.ensureRootDirectory()
        let relativePath: String = "\(bookID.uuidString).\(fileExtension)"
        let destination: URL = self.fileURL(relativePath: relativePath)

        let accessing: Bool = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        guard self.fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw BookFileStoreError.sourceUnreadable
        }
        if self.fileManager.fileExists(atPath: destination.path) {
            try self.fileManager.removeItem(at: destination)
        }
        try self.fileManager.copyItem(at: sourceURL, to: destination)

        let (sha256, byteCount): (String, Int) = try Self.digest(of: destination)
        return StoredBookFile(relativePath: relativePath, sha256: sha256, byteCount: byteCount)
    }

    func storeCover(_ data: Data, bookID: UUID) async throws -> String {
        try self.ensureRootDirectory()
        let relativePath: String = "\(bookID.uuidString).cover"
        try data.write(to: self.fileURL(relativePath: relativePath), options: .atomic)
        return relativePath
    }

    func removeFile(relativePath: String) async throws {
        let url: URL = self.fileURL(relativePath: relativePath)
        guard self.fileManager.fileExists(atPath: url.path) else {
            return
        }
        try self.fileManager.removeItem(at: url)
    }

    func fileURL(relativePath: String) -> URL {
        return self.rootDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }

    private func ensureRootDirectory() throws {
        try self.fileManager.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
    }

    /// 中文注释：分块读文件算 SHA-256，大文件（几百 MB 的 m4b）不整份进内存。
    private static func digest(of url: URL) throws -> (String, Int) {
        let handle: FileHandle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher: SHA256 = SHA256()
        var byteCount: Int = 0
        while true {
            let chunk: Data = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
            byteCount += chunk.count
        }
        let digest: String = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (digest, byteCount)
    }
}
