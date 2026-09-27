import Foundation
import Observation

/// coin 流水页的状态（设计书 30.8）：服务端为准、时间倒序、按游标翻页；本地不缓存。
@MainActor
@Observable
final class CoinLedgerViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    private(set) var entries: [CoinLedgerEntry] = []
    private(set) var state: State = .idle
    private(set) var nextCursor: String?
    private(set) var isLoadingMore: Bool = false

    private let accountClient: any PortalAccountFetching
    private let accessTokenProvider: any PortalAccessTokenProviding

    init(accountClient: any PortalAccountFetching, accessTokenProvider: any PortalAccessTokenProviding) {
        self.accountClient = accountClient
        self.accessTokenProvider = accessTokenProvider
    }

    var hasMore: Bool {
        return self.nextCursor != nil
    }

    /// 从最新一页重新加载。
    func load() async {
        self.state = .loading
        guard let page: CoinLedgerPage = await self.fetch(cursor: nil) else {
            self.state = .failed
            return
        }
        self.entries = page.entries
        self.nextCursor = page.nextCursor
        self.state = .loaded
    }

    /// 列表滚到末尾时再取一页；没有更多或正在取时不动。
    func loadMoreIfNeeded(current entry: CoinLedgerEntry) async {
        guard entry.id == self.entries.last?.id,
              let cursor: String = self.nextCursor,
              self.isLoadingMore == false else {
            return
        }
        self.isLoadingMore = true
        defer {
            self.isLoadingMore = false
        }
        guard let page: CoinLedgerPage = await self.fetch(cursor: cursor) else {
            return
        }
        let known: Set<String> = Set(self.entries.map(\.id))
        self.entries.append(contentsOf: page.entries.filter { known.contains($0.id) == false })
        self.nextCursor = page.nextCursor
    }

    private func fetch(cursor: String?) async -> CoinLedgerPage? {
        guard let accessToken: String = await self.accessTokenProvider.validAccessToken() else {
            return nil
        }
        return try? await self.accountClient.fetchLedger(accessToken: accessToken, cursor: cursor)
    }
}
