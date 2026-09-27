import Foundation

enum AdPointAccumulationResult: Equatable, Sendable {
    case noAdNeeded(
        previousPoints: Int,
        addedPoints: Int,
        pendingPoints: Int,
        threshold: Int,
        hasRemovedAds: Bool
    )
    case shouldPlayAd(
        previousPoints: Int,
        addedPoints: Int,
        pendingPoints: Int,
        threshold: Int,
        hasRemovedAds: Bool
    )

    var shouldPlayAd: Bool {
        switch self {
        case .noAdNeeded:
            return false
        case .shouldPlayAd:
            return true
        }
    }

    var pendingPoints: Int {
        switch self {
        case .noAdNeeded(_, _, let pendingPoints, _, _),
             .shouldPlayAd(_, _, let pendingPoints, _, _):
            return pendingPoints
        }
    }

    var debugDescription: String {
        switch self {
        case .noAdNeeded(
            let previousPoints,
            let addedPoints,
            let pendingPoints,
            let threshold,
            let hasRemovedAds
        ):
            return "result=noAdNeeded previous=\(previousPoints) added=\(addedPoints) pending=\(pendingPoints) threshold=\(threshold) hasRemovedAds=\(hasRemovedAds)"
        case .shouldPlayAd(
            let previousPoints,
            let addedPoints,
            let pendingPoints,
            let threshold,
            let hasRemovedAds
        ):
            return "result=shouldPlayAd previous=\(previousPoints) added=\(addedPoints) pending=\(pendingPoints) threshold=\(threshold) hasRemovedAds=\(hasRemovedAds)"
        }
    }
}

/// 中文注释：积分取值的单一定义点（设计书第 30 节 30.8，用户 2026-09-27 裁定）：
/// 漫画每换一章 +50；视频只计实际播放、每 600 秒 +50；满 100 弹一次激励广告。
enum AdPointRule {
    static let threshold: Int = 100
    static let comicPoints: Int = 50
    static let videoPoints: Int = 50
    /// 视频累计多少秒实际播放记一次 `videoPoints`。
    static let videoPlaybackInterval: TimeInterval = 600
}

// 中文注释：AccumulateAdPointsUseCase 集中处理广告积分阈值和去广告状态。
struct AccumulateAdPointsUseCase {
    private let repository: AppUserRepository
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let now: () -> Date

    init(
        repository: AppUserRepository,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.activeAppUser = activeAppUser
        self.now = now
    }

    func execute(
        userID: String? = nil,
        points: Int
    ) throws -> AdPointAccumulationResult {
        let userID: String = userID ?? self.activeAppUser?.currentUserID.uuidString ??
            AppUser.localDefaultID
        let now: Date = self.now()
        let addedPoints: Int = max(0, points)
        var user: AppUser = try self.repository.fetchUser(id: userID) ?? AppUser(
            id: userID,
            displayName: nil,
            hasRemovedAds: false,
            pendingAdPoints: 0,
            createdAt: now,
            updatedAt: now
        )
        let previousPoints: Int = user.pendingAdPoints

        if user.hasRemovedAds {
            if user.pendingAdPoints != 0 {
                user.pendingAdPoints = 0
                user.updatedAt = now
                try self.repository.saveUser(user)
            }

            #if DEBUG
            AppDebugLog.write(
                "[BrowseCraftAdPoints] skipped because ads removed " +
                "userID=\(userID) previous=\(previousPoints) added=\(addedPoints) pending=0"
            )
            #endif

            return .noAdNeeded(
                previousPoints: previousPoints,
                addedPoints: addedPoints,
                pendingPoints: 0,
                threshold: AdPointRule.threshold,
                hasRemovedAds: true
            )
        }

        // 中文注释：满额不在这里清零（30.8）——广告加载失败 / 无填充时积分要留到下个计分点再试，
        // 只有广告真的播过（看完或用户提前关闭）才由 `ConsumeAdPointsUseCase` 清零。
        user.pendingAdPoints = max(0, user.pendingAdPoints + addedPoints)
        let accumulatedPoints: Int = user.pendingAdPoints
        let shouldPlayAd: Bool = user.pendingAdPoints >= AdPointRule.threshold
        user.updatedAt = now
        try self.repository.saveUser(user)

        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftAdPoints] accumulated " +
            "userID=\(userID) previous=\(previousPoints) added=\(addedPoints) " +
            "accumulated=\(accumulatedPoints) pending=\(user.pendingAdPoints) " +
            "threshold=\(AdPointRule.threshold) shouldPlayAd=\(shouldPlayAd)"
        )
        #endif

        if shouldPlayAd {
            return .shouldPlayAd(
                previousPoints: previousPoints,
                addedPoints: addedPoints,
                pendingPoints: user.pendingAdPoints,
                threshold: AdPointRule.threshold,
                hasRemovedAds: false
            )
        }

        return .noAdNeeded(
            previousPoints: previousPoints,
            addedPoints: addedPoints,
            pendingPoints: user.pendingAdPoints,
            threshold: AdPointRule.threshold,
            hasRemovedAds: false
        )
    }
}

// 中文注释：广告真的播过之后（看完，或用户主动提前关闭）清掉累计积分；加载失败 / 无填充不调它，积分保留。
struct ConsumeAdPointsUseCase {
    private let repository: AppUserRepository
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let now: () -> Date

    init(
        repository: AppUserRepository,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.activeAppUser = activeAppUser
        self.now = now
    }

    func execute(userID: String? = nil) throws {
        let userID: String = userID ?? self.activeAppUser?.currentUserID.uuidString ??
            AppUser.localDefaultID
        guard var user: AppUser = try self.repository.fetchUser(id: userID),
              user.pendingAdPoints != 0 else {
            return
        }

        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftAdPoints] consumed userID=\(userID) previous=\(user.pendingAdPoints) pending=0"
        )
        #endif
        user.pendingAdPoints = 0
        user.updatedAt = self.now()
        try self.repository.saveUser(user)
    }
}
