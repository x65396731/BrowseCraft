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

        let result: AdPointAccumulationResult = try useCase.execute(points: AdPointRule.rssPoints)

        #expect(result.shouldPlayAd == false)
        #expect(result.pendingPoints == 30)
        #expect(
            result == .noAdNeeded(
                previousPoints: 20,
                addedPoints: AdPointRule.rssPoints,
                pendingPoints: 30,
                threshold: AdPointRule.threshold,
                hasRemovedAds: false
            )
        )
        #expect(repository.savedUser?.pendingAdPoints == 30)
    }

    @Test func triggersAdAtThresholdAndResetsPoints() throws {
        let repository: InMemoryAppUserRepository = InMemoryAppUserRepository(
            user: Self.user(pendingAdPoints: 90)
        )
        let useCase: AccumulateAdPointsUseCase = AccumulateAdPointsUseCase(
            repository: repository,
            now: { Self.now }
        )

        let result: AdPointAccumulationResult = try useCase.execute(points: AdPointRule.comicPoints)

        #expect(result.shouldPlayAd == true)
        #expect(result.pendingPoints == 0)
        #expect(
            result == .shouldPlayAd(
                previousPoints: 90,
                addedPoints: AdPointRule.comicPoints,
                pendingPoints: 0,
                threshold: AdPointRule.threshold,
                hasRemovedAds: false
            )
        )
        #expect(repository.savedUser?.pendingAdPoints == 0)
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

private final class InMemoryAppUserRepository: AppUserRepository {
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
