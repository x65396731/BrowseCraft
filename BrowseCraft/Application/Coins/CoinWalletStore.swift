import Foundation
import Observation

/// coin 余额的 App 侧状态（设计书 `video-pending-and-frozen-designs.md` 第 30 节）。
///
/// 中文注释：余额唯一权威在服务端，这里只是显示缓存——本地 `users` 行存一份，按 `revision`
/// 只进不退；四个刷新时机（启动、回到前台、看完广告后短轮询、收到生成推送 / 提交响应）都
/// 汇到 `apply` 这一处。未登录时不显示余额、看完广告不算 coin（30.6 已定）；那句「登入後才能獲得 coin」的提示
/// 由广告修饰器与设置页手动入口按结果显示（`AdPlaybackViewModel.message`），这里不管。
@MainActor
@Observable
final class CoinWalletStore: RewardedAdRewardCoordinating {
    /// 看完广告后的短轮询：SSV 回调通常晚几秒到服务端。
    static let adRewardPollDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(6)]

    /// nil = 未登录或还没同步过。
    private(set) var balance: Int?
    private(set) var revision: Int = 0
    private(set) var pricing: CoinPricing = .placeholder
    private(set) var isSignedIn: Bool = false
    /// 中文注释：两个端口对 Features 可见，供 `CoinLedgerViewModel` 的工厂扩展（在 Features）取用。
    let accountClient: any PortalAccountFetching
    let accessTokenProvider: any PortalAccessTokenProviding
    private let appUserRepository: any AppUserRepository
    private let activeAppUser: any ActiveAppUserProviding
    private let sleep: @Sendable (Duration) async throws -> Void
    /// 中文注释：余额接口回 401 时交给会话强制刷新一次（删除账号设计第 7.1 节）；nil 即只清余额显示（测试替身）。
    private let authorizationRejectionHandler: (any PortalAuthorizationRejectionHandling)?
    private var refreshTask: Task<Bool?, Never>?
    /// 中文注释：会话因 401 被清掉后通知界面刷新登录状态；组合根在 Features 装好后设置。
    @ObservationIgnored var didEndSession: (@MainActor () async -> Void)?

    init(
        accountClient: any PortalAccountFetching,
        accessTokenProvider: any PortalAccessTokenProviding,
        appUserRepository: any AppUserRepository,
        activeAppUser: any ActiveAppUserProviding,
        authorizationRejectionHandler: (any PortalAuthorizationRejectionHandling)? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.accountClient = accountClient
        self.accessTokenProvider = accessTokenProvider
        self.appUserRepository = appUserRepository
        self.activeAppUser = activeAppUser
        self.authorizationRejectionHandler = authorizationRejectionHandler
        self.sleep = sleep
        self.loadCached()
    }

    private var userID: String {
        return self.activeAppUser.currentUserID.uuidString
    }

    /// 中文注释：服务端账户 ID（小写 UUID），设置页展示给用户，运营用 `scripts/adjust_coins.py --user` 手动加减 coin。
    /// 登录态下活动用户与服务端会话同一个 ID（`refresh` 按此校验），所以这就是服务端的 app_user_id。
    var accountIdentifier: String {
        return self.activeAppUser.currentUserID.uuidString.lowercased()
    }

    /// 启动时先用本地缓存显示，再等服务端。
    func loadCached() {
        guard let user: AppUser = try? self.appUserRepository.fetchUser(id: self.userID),
              user.coinRevision > 0 else {
            return
        }
        self.balance = user.coinBalance
        self.revision = user.coinRevision
    }

    /// 向服务端要一次余额；没有会话即视为未登录（清显示、不清本地 revision 之外的东西）。
    /// 返回是否拿到了新读数。
    @discardableResult
    func refresh() async -> Bool {
        return await self.refresh(retryingAfterRejection: true)
    }

    private func refresh(retryingAfterRejection: Bool) async -> Bool {
        guard let accessToken: String = await self.accessTokenProvider.validAccessToken() else {
            self.markSignedOut()
            return false
        }
        do {
            let snapshot: PortalAccountSnapshot = try await self.accountClient.fetchAccount(accessToken: accessToken)
            guard snapshot.userID == self.activeAppUser.currentUserID else {
                return false
            }
            self.isSignedIn = true
            self.pricing = snapshot.pricing
            return self.apply(balance: snapshot.coinBalance, revision: snapshot.revision)
        } catch PortalAccountClientError.authRequired {
            // 中文注释：本机看来有效的 token 被服务端拒了（例如账号已在另一台设备删除）：让会话强制刷新一次再决定。
            guard retryingAfterRejection,
                  let handler: any PortalAuthorizationRejectionHandling = self.authorizationRejectionHandler else {
                self.markSignedOut()
                return false
            }
            switch await handler.handleAuthorizationRejected() {
            case .refreshed:
                return await self.refresh(retryingAfterRejection: false)
            case .signedOut:
                self.markSignedOut()
                await self.didEndSession?()
                return false
            case .unchanged:
                self.markSignedOut()
                return false
            }
        } catch {
            return false
        }
    }

    /// 只进不退：旧于本地版本号的读数丢掉（推送、提交响应、轮询可能乱序到达）。
    @discardableResult
    func apply(balance: Int, revision: Int) -> Bool {
        guard revision >= self.revision else {
            return false
        }
        let changed: Bool = revision > self.revision || self.balance != balance
        self.balance = balance
        self.revision = revision
        self.isSignedIn = true
        self.persist(balance: balance, revision: revision)
        return changed
    }

    /// 登出 / 换账号：清掉显示缓存，不迁移、不合并（30.6）。
    func markSignedOut() {
        self.isSignedIn = false
        self.balance = nil
        self.revision = 0
        self.persist(balance: 0, revision: 0)
    }

    /// 看完广告后短轮询至多三次，版本号前进即停。
    /// 返回是否到账：true 版本号前进了；false 三次都没前进（超时）；nil 轮询被取消（又看了一次广告等），结果不明。
    @discardableResult
    func pollAfterAdReward() async -> Bool? {
        let startRevision: Int = self.revision
        for delay: Duration in Self.adRewardPollDelays {
            guard (try? await self.sleep(delay)) != nil else {
                return nil
            }
            await self.refresh()
            if self.revision > startRevision {
                return true
            }
        }
        return false
    }

    // MARK: - RewardedAdRewardCoordinating

    var rewardedAdCoinAmount: Int {
        return self.pricing.adReward
    }

    /// 广告请求里带的用户标识：只有已登录才带（未登录看的广告不算 coin）。
    func rewardedAdUserIdentifier() async -> String? {
        guard await self.accessTokenProvider.validAccessToken() != nil else {
            return nil
        }
        return self.activeAppUser.currentUserID.uuidString.lowercased()
    }

    @discardableResult
    func rewardedAdCompleted(userIdentifier: String?) -> Task<Bool?, Never>? {
        guard userIdentifier != nil else {
            return nil
        }
        self.refreshTask?.cancel()
        let task: Task<Bool?, Never> = Task { [weak self] in
            return await self?.pollAfterAdReward() ?? nil
        }
        self.refreshTask = task
        return task
    }

    private func persist(balance: Int, revision: Int) {
        guard var user: AppUser = try? self.appUserRepository.fetchUser(id: self.userID) else {
            return
        }
        user.coinBalance = balance
        user.coinRevision = revision
        user.updatedAt = Date()
        try? self.appUserRepository.saveUser(user)
    }
}
