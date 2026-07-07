import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct VideoSourceImportDebugSnapshotTests {
    @Test func addVideoSourceInspectionReturnsFactsWithoutSaving() throws {
        let repository: VideoDebugSnapshotInMemorySourceRepository = VideoDebugSnapshotInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(sourceRepository: repository)

        let result: AddVideoSourceResult = try useCase.execute(
            entryURLString: "https://video.example.test/watch/sample",
            name: "Video Example",
            entryHTML: """
            <html>
              <body>
                <iframe src="/embed/sample"></iframe>
                <video><source src="https://media.example.test/sample.m3u8"></video>
              </body>
            </html>
            """,
            headers: ["User-Agent": "BrowseCraftTests"]
        )

        guard case .inspected(let inspection) = result else {
            Issue.record("Expected manual video source flow to inspect without saving.")
            return
        }

        #expect(inspection.baseURL.absoluteString == "https://video.example.test/")
        #expect(inspection.entryURL.absoluteString == "https://video.example.test/watch/sample")
        #expect(inspection.sourceName == "Video Example")
        #expect(inspection.logLines.contains("Headers: 1"))
        #expect(inspection.logLines.contains("HTML provided: yes"))
        #expect(inspection.logLines.contains("Contains iframe: yes"))
        #expect(inspection.logLines.contains("Contains video tag: yes"))
        #expect(inspection.logLines.contains("No video adapter or source type was inferred."))
        #expect(repository.savedSources.isEmpty)
    }

    @Test func addVideoSourceInspectionAcceptsNonMacCMSURL() throws {
        let repository: VideoDebugSnapshotInMemorySourceRepository = VideoDebugSnapshotInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(sourceRepository: repository)

        let result: AddVideoSourceResult = try useCase.execute(
            entryURLString: "https://video.example.test/topic/weekly.html",
            name: nil
        )

        guard case .inspected(let inspection) = result else {
            Issue.record("Expected non-MacCMS URL to remain inspectable.")
            return
        }

        #expect(inspection.entryURL.absoluteString == "https://video.example.test/topic/weekly.html")
        #expect(inspection.logLines.contains("HTML provided: no"))
        #expect(inspection.logLines.contains("No video adapter or source type was inferred."))
        #expect(repository.savedSources.isEmpty)
    }

    @Test func addVideoSourceDebugSnapshotIsNotProducedForManualInspection() throws {
        let repository: VideoDebugSnapshotInMemorySourceRepository = VideoDebugSnapshotInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(sourceRepository: repository)

        let debugResult: AddVideoSourceDebugResult = try useCase.executeWithDebugSnapshot(
            entryURLString: "https://video.example.test/"
        )

        guard case .inspected = debugResult.result else {
            Issue.record("Expected manual video source flow to return an inspection result.")
            return
        }

        #expect(debugResult.debugSnapshot == nil)
        #expect(repository.savedSources.isEmpty)
    }

    @Test func addVideoSourceRejectsInvalidURLWithoutSaving() throws {
        let repository: VideoDebugSnapshotInMemorySourceRepository = VideoDebugSnapshotInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(sourceRepository: repository)

        #expect(throws: VideoSourceURLResolverError.invalidURL) {
            _ = try useCase.execute(
                entryURLString: "not a url",
                name: "Invalid Video"
            )
        }
        #expect(repository.savedSources.isEmpty)
    }
}

private final class VideoDebugSnapshotInMemorySourceRepository: SourceRepository {
    var savedSources: [Source] = []

    func fetchSources() throws -> [Source] {
        return self.savedSources
    }

    func saveSource(_ source: Source) throws {
        self.savedSources.append(source)
    }

    func deleteSource(id: String) throws {
        self.savedSources.removeAll { source in
            source.id == id
        }
    }
}
