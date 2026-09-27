import Foundation
import Testing
@testable import BrowseCraft

struct AdPointUseCaseTests {
    @Test func accumulatesBelowThresholdWithoutAd() throws {
        let repository: InMemoryAppUserRepository = InMemoryAppUserRepository(
            user: Self.user(pendingAdPoints: 20)
        )
        let useCase: AccumulateAdPointsUseCase = AccumulateAdPointsUseCase(
            repository: repository,
            now: { Self.now }
        )

        let result: AdPointAccumulationResult = try useCase.execute(points: AdPointRule.comicPoints)

        #expect(result.shouldPlayAd == false)
        #expect(result.pendingPoints == 70)
        #expect(
            result == .noAdNeeded(
                previousPoints: 20,
                addedPoints: AdPointRule.comicPoints,
                pendingPoints: 70,
                threshold: AdPointRule.threshold,
                hasRemovedAds: false
            )
        )
        #expect(repository.savedUser?.pendingAdPoints == 70)
    }

    /// 满额只报 shouldPlayAd、不清零（30.8）：广告没播出来时积分留到下个计分点再试。
    @Test func triggersAdAtThresholdAndKeepsPointsUntilConsumed() throws {
        let repository: InMemoryAppUserRepository = InMemoryAppUserRepository(
            user: Self.user(pendingAdPoints: 60)
        )
        let useCase: AccumulateAdPointsUseCase = AccumulateAdPointsUseCase(
            repository: repository,
            now: { Self.now }
        )

        let result: AdPointAccumulationResult = try useCase.execute(points: AdPointRule.comicPoints)

        #expect(result.shouldPlayAd == true)
        #expect(result.pendingPoints == 110)
        #expect(
            result == .shouldPlayAd(
                previousPoints: 60,
                addedPoints: AdPointRule.comicPoints,
                pendingPoints: 110,
                threshold: AdPointRule.threshold,
                hasRemovedAds: false
            )
        )
        #expect(repository.savedUser?.pendingAdPoints == 110)

        // 没播出来 → 下个计分点再次满额
        let retry: AdPointAccumulationResult = try useCase.execute(points: AdPointRule.comicPoints)
        #expect(retry.shouldPlayAd == true)
        #expect(retry.pendingPoints == 160)

        // 播过了 → 清零
        try ConsumeAdPointsUseCase(repository: repository, now: { Self.now }).execute()
        #expect(repository.savedUser?.pendingAdPoints == 0)
        let afterConsume: AdPointAccumulationResult = try useCase.execute(points: AdPointRule.comicPoints)
        #expect(afterConsume.shouldPlayAd == false)
        #expect(afterConsume.pendingPoints == AdPointRule.comicPoints)
    }

    @Test func consumeWithoutPendingPointsWritesNothing() throws {
        let repository: InMemoryAppUserRepository = InMemoryAppUserRepository(
            user: Self.user(pendingAdPoints: 0)
        )

        try ConsumeAdPointsUseCase(repository: repository, now: { Self.now }).execute()

        #expect(repository.savedUser == nil)
    }

    @Test func removedAdsClearsPointsAndDoesNotTriggerAd() throws {
        let repository: InMemoryAppUserRepository = InMemoryAppUserRepository(
            user: Self.user(hasRemovedAds: true, pendingAdPoints: 90)
        )
        let useCase: AccumulateAdPointsUseCase = AccumulateAdPointsUseCase(
            repository: repository,
            now: { Self.now }
        )

        let result: AdPointAccumulationResult = try useCase.execute(points: AdPointRule.videoPoints)

        #expect(result.shouldPlayAd == false)
        #expect(result.pendingPoints == 0)
        #expect(
            result == .noAdNeeded(
                previousPoints: 90,
                addedPoints: AdPointRule.videoPoints,
                pendingPoints: 0,
                threshold: AdPointRule.threshold,
                hasRemovedAds: true
            )
        )
        #expect(repository.savedUser?.pendingAdPoints == 0)
        #expect(repository.savedUser?.hasRemovedAds == true)
    }

    private static let now: Date = Date(timeIntervalSince1970: 1_783_209_600)

    private static func user(
        hasRemovedAds: Bool = false,
        pendingAdPoints: Int = 0
    ) -> AppUser {
        return AppUser(
            id: AppUser.localDefaultID,
            displayName: "Local Default",
            hasRemovedAds: hasRemovedAds,
            pendingAdPoints: pendingAdPoints,
            createdAt: Self.now,
            updatedAt: Self.now
        )
    }
}

private final class InMemoryAppUserRepository: AppUserRepository, @unchecked Sendable {
    private var user: AppUser?
    private var transactionIDs: Set<String> = []
    private(set) var savedUser: AppUser?

    init(user: AppUser?) {
        self.user = user
    }

    func fetchUser(id: String) throws -> AppUser? {
        return self.user
    }

    func hasProcessedStoreKitTransaction(userID: String, transactionID: String) throws -> Bool {
        return self.transactionIDs.contains("\(userID):\(transactionID)")
    }

    func saveUser(_ user: AppUser) throws {
        self.user = user
        self.savedUser = user
    }

    func saveUser(_ user: AppUser, storeKitTransaction: UserStoreKitTransaction) throws {
        self.user = user
        self.savedUser = user
        self.transactionIDs.insert("\(storeKitTransaction.userID):\(storeKitTransaction.transactionID)")
    }
}
