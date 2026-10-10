import Foundation
import Observation

/// coin 流水页的状态（设计书 30.8）：服务端为准、时间倒序、按游标翻页；本地不缓存。
/// 中文注释：`@MainActor` 的界面状态属于 Features（architecture.md 第 2 节），2026-10-10 从 Application/Coins 搬来；
/// 只依赖两个 Application 端口。
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
    ///
    /// 中文注释：已经加载过（下拉刷新）时**不回到 `.loading`**——那会把列表换成转圈视图、拆掉刷新控件
    /// （系统警告「Attempting to change the refresh control while it is not idle」），刷新任务随之被取消。
    /// 取消不算失败；刷新失败时保留原列表，只有首次加载失败才显示「無法載入紀錄」。
    func load() async {
        let wasLoaded: Bool = self.state == .loaded
        if wasLoaded == false {
            self.state = .loading
        }
        switch await self.fetch(cursor: nil) {
        case .page(let page):
            self.entries = page.entries
            self.nextCursor = page.nextCursor
            self.state = .loaded
        case .cancelled:
            if wasLoaded == false {
                self.state = .idle
            }
        case .failed:
            if wasLoaded == false {
                self.state = .failed
            }
        }
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
        guard case .page(let page) = await self.fetch(cursor: cursor) else {
            return
        }
        let known: Set<String> = Set(self.entries.map(\.id))
        self.entries.append(contentsOf: page.entries.filter { known.contains($0.id) == false })
        self.nextCursor = page.nextCursor
    }

    private enum Fetch {
        case page(CoinLedgerPage)
        case cancelled
        case failed
    }

    private func fetch(cursor: String?) async -> Fetch {
        guard let accessToken: String = await self.accessTokenProvider.validAccessToken() else {
            return .failed
        }
        do {
            return .page(try await self.accountClient.fetchLedger(accessToken: accessToken, cursor: cursor))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return Task.isCancelled ? .cancelled : .failed
        }
    }
}

extension CoinWalletStore {
    /// 中文注释：设置页余额行点进去的流水页（30.8）；用同一个账户客户端与会话。放在 Features 里是因为
    /// Application 不得引用 Features 的类型（`BCA-ARCH-004`）。
    func makeLedgerViewModel() -> CoinLedgerViewModel {
        return CoinLedgerViewModel(accountClient: self.accountClient, accessTokenProvider: self.accessTokenProvider)
    }
}
