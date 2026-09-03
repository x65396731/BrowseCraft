import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：ReaderViewModel 状态机测试——脚本 reader runtime + 真实 GRDB 阅读历史/广告积分，
// 覆盖章节加载与历史落库、导航解析、失败、账号访问限制的登录提示与重试、阅读进度保存、广告积分阈值。
@MainActor
struct ReaderViewModelTests {
    private typealias Harness = ViewModelTestHarness

    private struct Fixture {
        let database: AppDatabase
        let source: Source
        let item: ContentItem
        let runtime: ScriptedSourceRuntime
        let userID: UUID
        let chapterURLs: [String]

        var comicHistoryRepository: GRDBComicChapterHistoryRepository {
            return GRDBComicChapterHistoryRepository(database: self.database)
        }

        func latestHistory() -> ComicChapterHistory? {
            return try? self.comicHistoryRepository.fetchLatest(
                userID: self.userID.uuidString,
                sourceID: self.source.id,
                comicItemID: self.item.id
            )
        }
    }

    private static func makeFixture() throws -> Fixture {
        let database: AppDatabase = try Harness.makeDatabase()
        let userID: UUID = UUID()
        try Harness.insertUser(userID, into: database)
        let source: Source = try Harness.makeComicSource()
        let item: ContentItem = Harness.makeItem(id: "comic-1", sourceID: source.id)
        let chapterURLs: [String] = (1...3).map { index in "https://example.test/comic/1/ch\(index)" }
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source)
        runtime.setReaderHandler { input in
            ScriptedSourceRuntime.readerOutput(
                sourceID: source.id,
                chapterURL: input.chapterURL,
                imageURLs: [
                    URL(string: "\(input.chapterURL.absoluteString)/p1.jpg")!,
                    URL(string: "\(input.chapterURL.absoluteString)/p2.jpg")!
                ]
            )
        }
        return Fixture(
            database: database,
            source: source,
            item: item,
            runtime: runtime,
            userID: userID,
            chapterURLs: chapterURLs
        )
    }

    private static func chapterLink(_ fixture: Fixture, index: Int) -> ChapterLink {
        return ChapterLink(
            title: "Chapter \(index + 1)",
            url: fixture.chapterURLs[index],
            navigationChapterURLs: fixture.chapterURLs,
            navigationChapterTitles: fixture.chapterURLs.indices.map { "Chapter \($0 + 1)" },
            navigationOrder: .ascending
        )
    }

    private static func makeViewModel(
        _ fixture: Fixture,
        selectedChapter: ChapterLink?,
        restoreContext: ReaderHistoryRestoreContext? = nil,
        credentialStore: (any SourceCredentialStoring)? = nil
    ) -> ReaderViewModel {
        return Harness.makeReaderViewModel(
            database: fixture.database,
            resolver: Harness.resolver([fixture.source.id: fixture.runtime]),
            source: fixture.source,
            item: fixture.item,
            userID: fixture.userID,
            selectedChapter: selectedChapter,
            restoreContext: restoreContext,
            credentialStore: credentialStore
        )
    }

    @Test func loadRequestsTheSelectedChapterAndRecordsHistory() async throws {
        let fixture: Fixture = try Self.makeFixture()
        let viewModel: ReaderViewModel = Self.makeViewModel(fixture, selectedChapter: Self.chapterLink(fixture, index: 1))

        await viewModel.load()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
        #expect(fixture.runtime.readerInputs.map { input in input.chapterURL.absoluteString } == [fixture.chapterURLs[1]])
        #expect(fixture.runtime.readerInputs.first?.context.sourceID == fixture.source.id)
        let chapter: ReaderChapter = try #require(viewModel.chapter)
        #expect(chapter.chapterURL == fixture.chapterURLs[1])
        #expect(chapter.pageImageURLs.count == 2)
        #expect(chapter.pageResources.count == 2)
        #expect(chapter.chapterTitle == "Chapter 2")
        #expect(Set([chapter.previousChapterURL, chapter.nextChapterURL]) == Set([fixture.chapterURLs[0], fixture.chapterURLs[2]]))

        let recorded: Bool = await Harness.waitUntil {
            fixture.latestHistory()?.chapterURL?.absoluteString == fixture.chapterURLs[1]
        }
        #expect(recorded)
        #expect(fixture.latestHistory()?.comicItemID == fixture.item.id)
    }

    @Test func loadingTheSameViewModelTwiceDoesNotRequestAgain() async throws {
        let fixture: Fixture = try Self.makeFixture()
        let viewModel: ReaderViewModel = Self.makeViewModel(fixture, selectedChapter: Self.chapterLink(fixture, index: 0))

        await viewModel.load()
        await viewModel.load()

        #expect(fixture.runtime.readerInputs.count == 1)
    }

    @Test func loadNextChapterFollowsResolvedNavigation() async throws {
        let fixture: Fixture = try Self.makeFixture()
        let viewModel: ReaderViewModel = Self.makeViewModel(fixture, selectedChapter: Self.chapterLink(fixture, index: 1))
        await viewModel.load()
        let nextURL: String = try #require(viewModel.chapter?.nextChapterURL)

        await viewModel.loadNextChapter()

        #expect(viewModel.pendingChapterNavigationDirection == .next)
        #expect(viewModel.chapter?.chapterURL == nextURL)
        #expect(fixture.runtime.readerInputs.last?.chapterURL.absoluteString == nextURL)
        #expect(viewModel.errorMessage == nil)

        viewModel.markChapterNavigationScrollHandled()
        #expect(viewModel.pendingChapterNavigationDirection == nil)
    }

    @Test func runtimeFailureSurfacesAnErrorMessage() async throws {
        let fixture: Fixture = try Self.makeFixture()
        fixture.runtime.setReaderHandler { _ in
            throw TestPortError(reason: "chapter unavailable")
        }
        let viewModel: ReaderViewModel = Self.makeViewModel(fixture, selectedChapter: Self.chapterLink(fixture, index: 0))

        await viewModel.load()

        #expect(viewModel.chapter == nil)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.sourceLoginPrompt == nil)
        #expect(fixture.latestHistory() == nil)
    }

    @Test func accessRequiredPromptsGuestLoginAndRetriesAfterCredential() async throws {
        let fixture: Fixture = try Self.makeFixture()
        let chapterURL: String = fixture.chapterURLs[0]
        fixture.runtime.setReaderHandler { _ in
            throw RuleExecutionError.accessRequired(stage: .reader, sourceID: fixture.source.id, url: chapterURL)
        }
        let credentialStore: InMemorySourceCredentialStore = InMemorySourceCredentialStore()
        let viewModel: ReaderViewModel = Self.makeViewModel(
            fixture,
            selectedChapter: Self.chapterLink(fixture, index: 0),
            credentialStore: credentialStore
        )

        await viewModel.load()

        #expect(viewModel.chapter == nil)
        #expect(viewModel.errorMessage == nil)
        let prompt: ReaderSourceLoginPrompt = try #require(viewModel.sourceLoginPrompt)
        #expect(prompt.state.sourceID == fixture.source.id)
        #expect(prompt.state.status == .guest)
        #expect(prompt.state.loginURL.absoluteString == "https://example.test/login")

        viewModel.requestSourceLogin(state: prompt.state)
        #expect(viewModel.sourceLoginPrompt == nil)
        #expect(viewModel.requestedSourceLogin?.sourceID == fixture.source.id)

        fixture.runtime.setReaderHandler { input in
            ScriptedSourceRuntime.readerOutput(
                sourceID: fixture.source.id,
                chapterURL: input.chapterURL,
                imageURLs: [URL(string: "\(input.chapterURL.absoluteString)/p1.jpg")!]
            )
        }
        await viewModel.completeRequestedSourceLogin(credential: SourceCredential(sourceID: fixture.source.id))

        #expect(viewModel.requestedSourceLogin == nil)
        #expect(credentialStore.credential(sourceID: fixture.source.id) != nil)
        #expect(viewModel.chapter?.chapterURL == chapterURL)
        #expect(fixture.runtime.readerInputs.count == 2)
    }

    @Test func visiblePageProgressIsPersisted() async throws {
        let fixture: Fixture = try Self.makeFixture()
        let viewModel: ReaderViewModel = Self.makeViewModel(fixture, selectedChapter: Self.chapterLink(fixture, index: 0))
        await viewModel.load()
        let chapter: ReaderChapter = try #require(viewModel.chapter)
        _ = await Harness.waitUntil { fixture.latestHistory() != nil }

        viewModel.updateVisiblePage(index: 1, imageURLString: chapter.pageImageURLs[1])
        viewModel.saveCurrentChapterProgress(reason: "test")

        let saved: Bool = await Harness.waitUntil {
            fixture.latestHistory()?.lastPageIndex == 1
        }
        #expect(saved)
        #expect(fixture.latestHistory()?.lastPageImageURL?.absoluteString == chapter.pageImageURLs[1])
    }

    @Test func restoreContextExposesThePendingPageUntilApplied() async throws {
        let fixture: Fixture = try Self.makeFixture()
        let viewModel: ReaderViewModel = Self.makeViewModel(
            fixture,
            selectedChapter: Self.chapterLink(fixture, index: 0),
            restoreContext: ReaderHistoryRestoreContext(lastPageIndex: 4, lastPageImageURLString: nil)
        )

        #expect(viewModel.pendingRestorePageIndex == 4)
        await viewModel.load()
        #expect(viewModel.pendingRestorePageIndex == 4)

        viewModel.markRestorePageApplied()

        #expect(viewModel.pendingRestorePageIndex == nil)
    }

    @Test func chapterLoadCrossingTheAdPointThresholdRequestsAnAd() async throws {
        let fixture: Fixture = try Self.makeFixture()
        let appUserRepository: GRDBAppUserRepository = GRDBAppUserRepository(database: fixture.database)
        var user: AppUser = try #require(try appUserRepository.fetchUser(id: fixture.userID.uuidString))
        user.pendingAdPoints = AdPointRule.threshold - AdPointRule.comicPoints
        try appUserRepository.saveUser(user)
        let viewModel: ReaderViewModel = Self.makeViewModel(fixture, selectedChapter: Self.chapterLink(fixture, index: 0))

        await viewModel.load()

        let requested: Bool = await Harness.waitUntil { viewModel.shouldPlayAd }
        #expect(requested)

        viewModel.markAdPlaybackHandled()

        #expect(viewModel.shouldPlayAd == false)
    }
}
