import Foundation

enum AdPointAccumulationResult: Equatable {
    case noAdNeeded(pendingPoints: Int)
    case shouldPlayAd(pendingPoints: Int)

    var shouldPlayAd: Bool {
        switch self {
        case .noAdNeeded:
            return false
        case .shouldPlayAd:
            return true
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
        var user: AppUser = try self.repository.fetchUser(id: userID) ?? AppUser(
            id: userID,
            displayName: nil,
            hasRemovedAds: false,
            pendingAdPoints: 0,
            createdAt: now,
            updatedAt: now
        )

        if user.hasRemovedAds {
            if user.pendingAdPoints != 0 {
                user.pendingAdPoints = 0
                user.updatedAt = now
                try self.repository.saveUser(user)
            }

            return .noAdNeeded(pendingPoints: 0)
        }

        user.pendingAdPoints = max(0, user.pendingAdPoints + max(0, points))
        let shouldPlayAd: Bool = user.pendingAdPoints >= AdPointRule.threshold
        if shouldPlayAd {
            user.pendingAdPoints = 0
        }
        user.updatedAt = now
        try self.repository.saveUser(user)

        if shouldPlayAd {
            return .shouldPlayAd(pendingPoints: user.pendingAdPoints)
        }

        return .noAdNeeded(pendingPoints: user.pendingAdPoints)
    }
}
