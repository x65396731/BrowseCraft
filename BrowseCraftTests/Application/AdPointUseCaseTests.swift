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

        #expect(result == .noAdNeeded(pendingPoints: 30))
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

        #expect(result == .shouldPlayAd(pendingPoints: 0))
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

        #expect(result == .noAdNeeded(pendingPoints: 0))
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
    private(set) var savedUser: AppUser?

    init(user: AppUser?) {
        self.user = user
    }

    func fetchUser(id: String) throws -> AppUser? {
        return self.user
    }

    func saveUser(_ user: AppUser) throws {
        self.user = user
        self.savedUser = user
    }
}
