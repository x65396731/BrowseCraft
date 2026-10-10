import Foundation
import Testing
@testable import BrowseCraft

/// coin 流水页（设计书 30.8）：首页加载、滚到末尾按游标翻页、去重、没有会话即失败。
@MainActor
struct CoinLedgerViewModelTests {
    @Test func loadsFirstPageThenFollowsCursorWithoutDuplicates() async throws {
        let fetcher: PagedLedgerFetcher = PagedLedgerFetcher(pages: [
            nil: CoinLedgerPage(entries: [Self.entry("e3", delta: -100), Self.entry("e2", delta: 20)], nextCursor: "c1"),
            "c1": CoinLedgerPage(entries: [Self.entry("e2", delta: 20), Self.entry("e1", delta: 100)], nextCursor: nil),
        ])
        let viewModel: CoinLedgerViewModel = CoinLedgerViewModel(accountClient: fetcher, accessTokenProvider: TokenProvider(token: "t"))

        await viewModel.load()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.entries.map(\.id) == ["e3", "e2"])
        #expect(viewModel.hasMore)

        await viewModel.loadMoreIfNeeded(current: viewModel.entries[0])
        #expect(viewModel.entries.count == 2, "不是末条，不翻页")

        await viewModel.loadMoreIfNeeded(current: viewModel.entries[1])
        #expect(viewModel.entries.map(\.id) == ["e3", "e2", "e1"], "重叠的 e2 只留一条")
        #expect(viewModel.hasMore == false)
        #expect(fetcher.cursors == [nil, "c1"])
    }

    @Test func failsWithoutSessionOrOnTransportError() async throws {
        let signedOut: CoinLedgerViewModel = CoinLedgerViewModel(
            accountClient: PagedLedgerFetcher(pages: [:]),
            accessTokenProvider: TokenProvider(token: nil)
        )
        await signedOut.load()
        #expect(signedOut.state == .failed)

        let broken: CoinLedgerViewModel = CoinLedgerViewModel(
            accountClient: PagedLedgerFetcher(pages: [:]),
            accessTokenProvider: TokenProvider(token: "t")
        )
        await broken.load()
        #expect(broken.state == .failed)
    }

    /// 下拉刷新：已加载时不回到 loading（否则列表被拆、刷新控件报警）；刷新失败或被取消都保留原列表。
    @Test func refreshKeepsTheListWhenItFailsOrIsCancelled() async throws {
        let fetcher: PagedLedgerFetcher = PagedLedgerFetcher(pages: [
            nil: CoinLedgerPage(entries: [Self.entry("e1", delta: 100)], nextCursor: nil),
        ])
        let viewModel: CoinLedgerViewModel = CoinLedgerViewModel(accountClient: fetcher, accessTokenProvider: TokenProvider(token: "t"))
        await viewModel.load()
        #expect(viewModel.state == .loaded)

        fetcher.failNext = .transport
        await viewModel.load()
        #expect(viewModel.state == .loaded, "刷新失败不换成「無法載入」")
        #expect(viewModel.entries.map(\.id) == ["e1"])

        fetcher.failNext = .cancelled
        await viewModel.load()
        #expect(viewModel.state == .loaded, "刷新被取消不算失败")
        #expect(viewModel.entries.map(\.id) == ["e1"])
    }

    @Test func firstLoadCancellationGoesBackToIdleNotFailed() async throws {
        let fetcher: PagedLedgerFetcher = PagedLedgerFetcher(pages: [:])
        fetcher.failNext = .cancelled
        let viewModel: CoinLedgerViewModel = CoinLedgerViewModel(accountClient: fetcher, accessTokenProvider: TokenProvider(token: "t"))
        await viewModel.load()
        #expect(viewModel.state == .idle)
    }

    private static func entry(_ id: String, delta: Int) -> CoinLedgerEntry {
        return CoinLedgerEntry(id: id, delta: delta, reason: .adReward, balanceAfter: 0, createdAt: Date(timeIntervalSince1970: 1_000))
    }
}

private final class PagedLedgerFetcher: PortalAccountFetching, @unchecked Sendable {
    enum Failure {
        case transport
        case cancelled
    }

    private let pages: [String?: CoinLedgerPage]
    private(set) var cursors: [String?] = []
    /// 下一次 fetchLedger 以此失败（用后即清）。
    var failNext: Failure?

    init(pages: [String?: CoinLedgerPage]) {
        self.pages = pages
    }

    func fetchAccount(accessToken: String) async throws -> PortalAccountSnapshot {
        throw PortalAccountClientError.transport
    }

    func fetchLedger(accessToken: String, cursor: String?) async throws -> CoinLedgerPage {
        self.cursors.append(cursor)
        if let failure: Failure = self.failNext {
            self.failNext = nil
            switch failure {
            case .transport:
                throw PortalAccountClientError.transport
            case .cancelled:
                throw CancellationError()
            }
        }
        guard let page: CoinLedgerPage = self.pages[cursor] else {
            throw PortalAccountClientError.transport
        }
        return page
    }
}

private struct TokenProvider: PortalAccessTokenProviding {
    let token: String?

    func validAccessToken() async -> String? {
        return self.token
    }
}
