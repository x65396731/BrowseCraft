import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：Readium 适配器在真实夹具上的固定输入：一本最小 EPUB（两章、封面、作者）、一段 2 秒 mp3、一段带元数据的 m4a。

struct ReadiumBookAdapterTests {
    @Test func inspectorRecognisesEPUBAndAudioAndRejectsOthers() async throws {
        let inspector: ReadiumBookFileInspector = ReadiumBookFileInspector()

        #expect(try await inspector.inspect(fileURL: Self.fixture("fixture-book", "epub")) == .supported(.epub, fileExtension: "epub"))
        #expect(try await inspector.inspect(fileURL: Self.fixture("fixture-tone", "mp3")) == .supported(.audiobook, fileExtension: "mp3"))
        #expect(try await inspector.inspect(fileURL: Self.fixture("fixture-tone", "m4a")) == .supported(.audiobook, fileExtension: "m4a"))

        let text: URL = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        #expect(try await inspector.inspect(fileURL: text) == .unsupported)
    }

    @Test func openerReadsEPUBMetadataAndCover() async throws {
        let opener: ReadiumBookPublicationOpener = ReadiumBookPublicationOpener()

        let handle: BookPublicationHandle = try await opener.openPublication(fileURL: Self.fixture("fixture-book", "epub"), format: .epub)

        #expect(handle.metadata.title == "Fixture Book")
        #expect(handle.metadata.author == "Fixture Author")
        #expect(handle.metadata.isRestricted == false)
        #expect((handle.metadata.coverImageData?.count ?? 0) > 0)
        let readium: ReadiumBookPublicationHandle = try #require(handle as? ReadiumBookPublicationHandle)
        #expect(readium.publication.readingOrder.count == 2)
    }

    @Test func openerOpensSingleAudioFileAsAudiobook() async throws {
        let opener: ReadiumBookPublicationOpener = ReadiumBookPublicationOpener()

        let handle: BookPublicationHandle = try await opener.openPublication(fileURL: Self.fixture("fixture-tone", "m4a"), format: .audiobook)

        #expect(handle.metadata.isRestricted == false)
        let readium: ReadiumBookPublicationHandle = try #require(handle as? ReadiumBookPublicationHandle)
        #expect(readium.publication.readingOrder.count == 1)
        #expect(readium.publication.readingOrder.first?.mediaType?.isAudio == true)
    }

    @Test func openerRejectsFormatMismatchAndMissingFile() async throws {
        let opener: ReadiumBookPublicationOpener = ReadiumBookPublicationOpener()

        await #expect(throws: BookPublicationOpenError.unsupportedFormat) {
            _ = try await opener.openPublication(fileURL: Self.fixture("fixture-tone", "mp3"), format: .epub)
        }
        await #expect(throws: BookPublicationOpenError.fileMissing) {
            _ = try await opener.openPublication(fileURL: URL(fileURLWithPath: "/nonexistent/book.epub"), format: .epub)
        }
    }

    private static func fixture(_ name: String, _ ext: String) throws -> URL {
        return try #require(Bundle(for: FixtureBundleMarker.self).url(forResource: name, withExtension: ext))
    }
}

private final class FixtureBundleMarker {}
