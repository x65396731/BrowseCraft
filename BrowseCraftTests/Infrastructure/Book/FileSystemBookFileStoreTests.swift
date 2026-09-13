import CryptoKit
import Foundation
import Testing
@testable import BrowseCraft

struct FileSystemBookFileStoreTests {
    @Test func copiesFileAndReportsDigestAndSize() async throws {
        let root: URL = Self.temporaryDirectory()
        let store: FileSystemBookFileStore = FileSystemBookFileStore(rootDirectory: root)
        let source: URL = Self.temporaryDirectory().appendingPathComponent("source.epub")
        let payload: Data = Data(repeating: 0xAB, count: 3 * 1024 * 1024 + 17)
        try payload.write(to: source)
        let bookID: UUID = UUID()

        let stored: StoredBookFile = try await store.storeBookFile(from: source, bookID: bookID, fileExtension: "epub")

        #expect(stored.relativePath == "\(bookID.uuidString).epub")
        #expect(stored.byteCount == payload.count)
        #expect(stored.sha256 == SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined())
        #expect(try Data(contentsOf: store.fileURL(relativePath: stored.relativePath)) == payload)
        #expect(FileManager.default.fileExists(atPath: source.path), "原文件不动")
    }

    @Test func storesCoverAndRemovesFilesIdempotently() async throws {
        let store: FileSystemBookFileStore = FileSystemBookFileStore(rootDirectory: Self.temporaryDirectory())
        let bookID: UUID = UUID()

        let coverPath: String = try await store.storeCover(Data([1, 2, 3]), bookID: bookID)
        #expect(coverPath == "\(bookID.uuidString).cover")
        #expect(try Data(contentsOf: store.fileURL(relativePath: coverPath)) == Data([1, 2, 3]))

        try await store.removeFile(relativePath: coverPath)
        #expect(FileManager.default.fileExists(atPath: store.fileURL(relativePath: coverPath).path) == false)
        try await store.removeFile(relativePath: coverPath)
    }

    @Test func unreadableSourceIsRejectedWithoutLeavingFiles() async throws {
        let root: URL = Self.temporaryDirectory()
        let store: FileSystemBookFileStore = FileSystemBookFileStore(rootDirectory: root)
        let missing: URL = Self.temporaryDirectory().appendingPathComponent("missing.epub")

        await #expect(throws: BookFileStoreError.sourceUnreadable) {
            _ = try await store.storeBookFile(from: missing, bookID: UUID(), fileExtension: "epub")
        }
        let contents: [String] = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        #expect(contents.isEmpty)
    }

    private static func temporaryDirectory() -> URL {
        let url: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftBookStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
