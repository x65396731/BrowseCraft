import Foundation

enum AdPointAccumulationResult: Equatable {
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

enum AdPointRule {
    static let threshold: Int = 100
    static let rssPoints: Int = 10
    static let comicPoints: Int = 20
    static let videoPoints: Int = 50
}

// 中文注释：AccumulateAdPointsUseCase 集中处理广告积分阈值和去广告状态。
struct AccumulateAdPointsUseCase {
    private let repository: AppUserRepository
    private let now: () -> Date

    init(
        repository: AppUserRepository,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.now = now
    }

    func execute(
        userID: String = AppUser.localDefaultID,
        points: Int
    ) throws -> AdPointAccumulationResult {
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
            print(
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

        user.pendingAdPoints = max(0, user.pendingAdPoints + addedPoints)
        let accumulatedPoints: Int = user.pendingAdPoints
        let shouldPlayAd: Bool = user.pendingAdPoints >= AdPointRule.threshold
        if shouldPlayAd {
            user.pendingAdPoints = 0
        }
        user.updatedAt = now
        try self.repository.saveUser(user)

        #if DEBUG
        print(
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
