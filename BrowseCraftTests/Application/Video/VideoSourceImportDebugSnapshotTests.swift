import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct VideoSourceImportDebugSnapshotTests {
    @Test func videoImportResultFormatterUsesUserFacingAggregateMessages() throws {
        let source: Source = try Self.makeGenericVideoSource(id: "video.formatter")

        #expect(VideoSourceImportResultFormatter.message(for: .saved(source)) == VideoSourceImportStrings.saved)
        #expect(VideoSourceImportResultFormatter.message(for: .needsReview(source, warnings: ["internal warning"])) == VideoSourceImportStrings.needsReview)
        #expect(VideoSourceImportResultFormatter.message(for: .unavailable(.noVideoSignals)) == VideoSourceImportStrings.unavailable)
        #expect(VideoSourceImportResultFormatter.message(for: .unavailable(.lowConfidence)) == VideoSourceImportStrings.unavailable)
        #expect(VideoSourceImportResultFormatter.message(for: .pluginRequired(.encryptedPlayback)) == VideoSourceImportStrings.pluginRequired)
    }

    @Test func addVideoSourceDebugSnapshotExplainsSavedGenericHTMLImport() throws {
        let repository: VideoDebugSnapshotInMemorySourceRepository = VideoDebugSnapshotInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: repository,
            now: Self.makeClock(),
            makeID: { "video.saved" }
        )

        let debugResult: AddVideoSourceDebugResult = try useCase.executeWithDebugSnapshot(
            entryURLString: "https://video.example.test/",
            name: "Video Example",
            entryHTML: """
            <html>
              <body>
                <article class="video-card thumb-block duration thumbnail">
                  <video><source src="https://media.example.test/sample.m3u8"></video>
                  <img data-src="/cover.jpg">
                  <a href="/watch/sample">Sample</a>
                </article>
              </body>
            </html>
            """
        )

        if case .saved(let source) = debugResult.result {
            #expect(source.id == "video.saved")
        } else {
            Issue.record("Expected high-confidence generic HTML video import to save.")
        }

        #expect(repository.savedSources.map(\.id) == ["video.saved"])
        #expect(debugResult.debugSnapshot.sourceKind == .video)
        #expect(debugResult.debugSnapshot.structure?.kind == .genericHTML)
        #expect(debugResult.debugSnapshot.importDecision?.branch == .saved)
        #expect(debugResult.debugSnapshot.signals.contains { signal in
            signal.id == "video.importDecision" && signal.value == "saved"
        })
        #expect(debugResult.debugSnapshot.issues.isEmpty)
        #expect(debugResult.debugSnapshot.status == .succeeded)
    }

    @Test func addVideoSourceDebugSnapshotExplainsUnavailableImport() throws {
        let repository: VideoDebugSnapshotInMemorySourceRepository = VideoDebugSnapshotInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: repository,
            now: Self.makeClock(),
            makeID: { "video.unavailable" }
        )

        let debugResult: AddVideoSourceDebugResult = try useCase.executeWithDebugSnapshot(
            entryURLString: "https://article.example.test/",
            name: "Not Video",
            entryHTML: """
            <html>
              <body>
                <h1>About this site</h1>
                <p>Company profile and contact information.</p>
              </body>
            </html>
            """
        )

        #expect(debugResult.result == .unavailable(.noVideoSignals))
        #expect(repository.savedSources.isEmpty)
        #expect(debugResult.debugSnapshot.structure?.kind == .unknown)
        #expect(debugResult.debugSnapshot.importDecision?.branch == .unavailable)
        #expect(debugResult.debugSnapshot.importDecision?.reason == "noVideoSignals")
        #expect(debugResult.debugSnapshot.issues.first?.category == .structureDetection)
        #expect(debugResult.debugSnapshot.status == .failed)
    }

    @Test func addVideoSourceDebugSnapshotExplainsPluginRequiredImport() throws {
        let repository: VideoDebugSnapshotInMemorySourceRepository = VideoDebugSnapshotInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: repository,
            now: Self.makeClock(),
            makeID: { "video.plugin" }
        )

        let debugResult: AddVideoSourceDebugResult = try useCase.executeWithDebugSnapshot(
            entryURLString: "https://video.example.test/",
            name: "Plugin Video",
            entryHTML: """
            <html>
              <body>
                <script>var media = CryptoJS.AES.decrypt(payload, key)</script>
              </body>
            </html>
            """
        )

        #expect(debugResult.result == .pluginRequired(.encryptedPlayback))
        #expect(repository.savedSources.isEmpty)
        #expect(debugResult.debugSnapshot.structure?.kind == .pluginRequired)
        #expect(debugResult.debugSnapshot.importDecision?.branch == .pluginRequired)
        #expect(debugResult.debugSnapshot.importDecision?.reason == "encryptedPlayback")
        #expect(debugResult.debugSnapshot.issues.first?.category == .missingCapability)
        #expect(debugResult.debugSnapshot.status == .failed)
    }

    @Test func addVideoSourceRejectsInvalidURLWithoutSaving() throws {
        let repository: VideoDebugSnapshotInMemorySourceRepository = VideoDebugSnapshotInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: repository,
            now: Self.makeClock(),
            makeID: { "video.invalid" }
        )

        #expect(throws: VideoSourceURLResolverError.invalidURL) {
            _ = try useCase.execute(
                entryURLString: "not a url",
                name: "Invalid Video"
            )
        }
        #expect(repository.savedSources.isEmpty)
    }

    @Test func savedGenericHTMLVideoSourceLoadsListAfterSaving() async throws {
        let repository: VideoDebugSnapshotInMemorySourceRepository = VideoDebugSnapshotInMemorySourceRepository()
        let useCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: repository,
            now: Self.makeClock(),
            makeID: { "video.saved.load" }
        )
        let result: AddVideoSourceResult = try useCase.execute(
            entryURLString: "https://video.example.test/",
            name: "Saved Video",
            entryHTML: """
            <html>
              <body>
                <article class="video-card thumb-block duration thumbnail">
                  <video><source src="https://media.example.test/a.m3u8"></video>
                  <img data-src="/covers/a.jpg" alt="Episode A">
                  <a href="/watch/a" title="Episode A">Episode A</a>
                  <span class="duration">12:00</span>
                </article>
              </body>
            </html>
            """
        )

        guard case .saved(let savedSource) = result else {
            Issue.record("Expected high-confidence generic HTML video source to save.")
            return
        }

        let definition: SourceDefinition = SourceDefinitionMapper().definition(from: savedSource)
        let htmlLoader: FixtureVideoPageContentLoader = FixtureVideoPageContentLoader(
            html: """
            <html>
              <body>
                <article class="video-card thumb-block duration thumbnail">
                  <video><source src="https://media.example.test/a.m3u8"></video>
                  <img data-src="/covers/a.jpg" alt="Episode A">
                  <a href="/watch/a" title="Episode A">Episode A</a>
                  <span class="duration">12:00</span>
                </article>
              </body>
            </html>
            """
        )
        let mapper: any VideoHTMLMapper = GenericHTMLVideoHTMLMapper()
        let runtime: VideoSourceRuntime = VideoSourceRuntime(
            definition: definition,
            listLoader: VideoSourceListLoader(pageContentLoader: htmlLoader, mapper: mapper),
            detailLoader: VideoSourceDetailLoader(pageContentLoader: htmlLoader, mapper: mapper),
            playbackLoader: VideoSourcePlaybackLoader(pageContentLoader: htmlLoader, mapper: mapper)
        )
        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: SourceRuntimeContext(
                    sourceID: savedSource.id,
                    pageID: nil,
                    tabID: nil,
                    ruleID: nil,
                    requestOverride: nil,
                    debugMode: false,
                    operation: .list
                )
            )
        )

        #expect(repository.savedSources.map(\.id) == ["video.saved.load"])
        #expect(output.items.map(\.title) == ["Episode A"])
        #expect(output.diagnostics.status == .succeeded)
    }

    private static func makeClock() -> () -> Date {
        var offset: TimeInterval = 0
        return {
            defer {
                offset += 1
            }
            return Date(timeIntervalSince1970: 1_800_000_000 + offset)
        }
    }

    private static func makeGenericVideoSource(id: String) throws -> Source {
        let entryURL: URL = try #require(URL(string: "https://video.example.test/"))
        let timestamp: Date = Date(timeIntervalSince1970: 1_800_000_000)
        return Source(
            id: id,
            name: "Video Example",
            baseURL: entryURL.absoluteString,
            type: .html,
            configuration: .video(
                VideoSourceConfiguration(
                    definition: VideoSourceDefinition(
                        adapter: .genericHTML,
                        entryURL: entryURL,
                        seedURL: nil,
                        entryKind: .home,
                        routePatterns: nil,
                        playbackPolicy: .playPageFirst,
                        requiresAccount: false,
                        seedVodID: nil,
                        seedSourceIndex: nil,
                        seedEpisodeIndex: nil,
                        seedDetailURL: nil,
                        seedPlayURL: nil
                    ),
                    listTabs: []
                )
            ),
            enabled: true,
            createdAt: timestamp,
            updatedAt: timestamp
        )
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

private struct FixtureVideoPageContentLoader: PageContentLoader {
    let html: String

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        return self.html
    }
}
