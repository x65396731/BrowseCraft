import Foundation
import Testing
import BrowseCraftCore
import BrowseCraftDomain
@testable import BrowseCraft

// 中文注释：翻页失败只进分页脚（2026-10-10 裁定）：已加载的内容照留、不进弹框用的 `errorMessage`，
// 分页脚换成「加载失败，再滑到底重试」并带原因；再次触底成功后恢复原状。
@MainActor
struct LibraryPaginationFailureTests {
    private typealias Harness = ViewModelTestHarness

    @Test func nextPageFailureGoesToTheFooterAndTheNextAttemptClearsIt() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let source: Source = try Harness.makeComicSource()
        try GRDBSourceRepository(database: database).saveSource(source)
        let attempts: AttemptCounter = AttemptCounter()
        let runtime: ScriptedSourceRuntime = ScriptedSourceRuntime(source: source, list: { input in
            switch input.page {
            case 1:
                return ScriptedSourceRuntime.listOutput(ids: ["a", "b"], nextPage: 2)
            case 2:
                if attempts.next() == 1 {
                    throw RuleExecutionError.httpStatus(url: "https://example.test/list?page=2", statusCode: 503)
                }
                return ScriptedSourceRuntime.listOutput(ids: ["c"], nextPage: nil)
            default:
                throw TestPortError(reason: "unexpected page \(input.page)")
            }
        })
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([source.id: runtime])
        )
        _ = await viewModel.loadIfNeeded()
        #expect(viewModel.items.map(\.id) == ["a", "b"])

        await viewModel.loadNextPageIfNeeded()

        #expect(viewModel.items.map(\.id) == ["a", "b"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.selectedListTabErrorMessage == nil)
        #expect(viewModel.nextPageErrorMessage != nil)
        #expect(viewModel.isLoadingNextPage == false)
        #expect(viewModel.canLoadNextPage)
        #expect(viewModel.shouldShowPaginationStatus)
        #expect(viewModel.paginationStatusText == String(format: NSLocalizedString("library_pagination_failed", comment: ""), String(format: NSLocalizedString("library_pagination_page", comment: ""), 1)))

        await viewModel.loadNextPageIfNeeded()

        #expect(viewModel.items.map(\.id) == ["a", "b", "c"])
        #expect(viewModel.nextPageErrorMessage == nil)
        #expect(viewModel.currentListPage == 2)
        #expect(viewModel.paginationStatusText == String(format: NSLocalizedString("library_pagination_end", comment: ""), String(format: NSLocalizedString("library_pagination_page", comment: ""), 2)))
        #expect(runtime.listInputs.map(\.page) == [1, 2, 2])
    }

    @Test func switchingSourceDropsAStalePaginationFailure() async throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let first: Source = try Harness.makeComicSource(id: "built-in.comic", name: "First")
        let second: Source = try Harness.makeComicSource(id: "comic.custom", name: "Second")
        let repository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        try repository.saveSource(first)
        try repository.saveSource(second)
        // 中文注释：内置来源不占位置，测试库的位置上限是 1，所以一个内置 + 一个自定义（与 LibraryViewModelTests 的切源用例同一写法）；两个来源都是第 1 页成功、第 2 页失败，无论启动选中哪一个翻页都会失败。
        let failingList: ScriptedSourceRuntime.ListHandler = { input in
            if input.page == 1 {
                return ScriptedSourceRuntime.listOutput(ids: ["a"], nextPage: 2)
            }
            throw RuleExecutionError.httpStatus(url: "https://example.test/list?page=2", statusCode: 500)
        }
        let store: SourceSelectionStore = SourceSelectionStore()
        let viewModel: LibraryViewModel = Harness.makeLibraryViewModel(
            database: database,
            resolver: Harness.resolver([
                first.id: ScriptedSourceRuntime(source: first, list: failingList),
                second.id: ScriptedSourceRuntime(source: second, list: failingList)
            ]),
            selectionStore: store
        )
        _ = await viewModel.loadIfNeeded()
        let initialSourceID: String = try #require(viewModel.selectedSourceID)
        let otherSourceID: String = initialSourceID == first.id ? second.id : first.id
        await viewModel.loadNextPageIfNeeded()
        #expect(viewModel.nextPageErrorMessage != nil)

        store.selectedSourceID = otherSourceID

        let switched: Bool = await Harness.waitUntil {
            viewModel.selectedSourceID == otherSourceID
        }
        #expect(switched)
        #expect(viewModel.nextPageErrorMessage == nil)
        #expect(viewModel.shouldShowPaginationStatus == false)
    }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var count: Int = 0

    func next() -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.count += 1
        return self.count
    }
}
