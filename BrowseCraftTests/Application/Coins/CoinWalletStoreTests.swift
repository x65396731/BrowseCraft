import Foundation
import Testing
@testable import BrowseCraft

/// 设计书第 30 节：余额只进不退、登出清缓存、未登录看广告不计 coin、看完广告后短轮询到版本号前进为止。
@MainActor
struct CoinWalletStoreTests {
    private static let userID: UUID = UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!

    @Test func refreshAppliesServerSnapshotAndPersists() async throws {
        let fixture: Fixture = Fixture(snapshots: [Fixture.snapshot(balance: 100, revision: 1)])
        let changed: Bool = await fixture.store.refresh()
        #expect(changed)
        #expect(fixture.store.balance == 100)
        #expect(fixture.store.revision == 1)
        #expect(fixture.store.isSignedIn)
        #expect(fixture.store.pricing.normal == 100)
        let user: AppUser? = try fixture.repository.fetchUser(id: Self.userID.uuidString)
        #expect(user?.coinBalance == 100)
        #expect(user?.coinRevision == 1)
    }

    @Test func staleRevisionIsIgnoredAndNewerWins() async throws {
        let fixture: Fixture = Fixture(snapshots: [Fixture.snapshot(balance: 100, revision: 3)])
        await fixture.store.refresh()
        #expect(fixture.store.apply(balance: 200, revision: 2) == false)
        #expect(fixture.store.balance == 100)
        #expect(fixture.store.apply(balance: 0, revision: 4))
        #expect(fixture.store.balance == 0)
    }

    @Test func signedOutClearsCacheAndAnonymousAdOnlyHints() async throws {
        let fixture: Fixture = Fixture(snapshots: [Fixture.snapshot(balance: 100, revision: 1)])
        await fixture.store.refresh()
        fixture.store.markSignedOut()
        #expect(fixture.store.balance == nil)
        #expect(fixture.store.isSignedIn == false)
        #expect(try fixture.repository.fetchUser(id: Self.userID.uuidString)?.coinRevision == 0)

        fixture.tokenProvider.token = nil
        #expect(await fixture.store.rewardedAdUserIdentifier() == nil)
        fixture.store.rewardedAdCompleted(userIdentifier: nil)
        #expect(fixture.fetcher.calls == 1, "未登录看完广告不去拉余额")
    }

    @Test func pollAfterAdRewardStopsOnceRevisionAdvances() async throws {
        let fixture: Fixture = Fixture(
            snapshots: [
                Fixture.snapshot(balance: 100, revision: 1),
                Fixture.snapshot(balance: 100, revision: 1),
                Fixture.snapshot(balance: 120, revision: 2),
                Fixture.snapshot(balance: 999, revision: 9),
            ]
        )
        await fixture.store.refresh()
        #expect(await fixture.store.rewardedAdUserIdentifier() == Self.userID.uuidString.lowercased())
        await fixture.store.pollAfterAdReward()
        #expect(fixture.store.balance == 120)
        #expect(fixture.fetcher.calls == 3, "第二次轮询版本号前进即停，不再第三次")
    }

    @Test func cachedRowIsShownBeforeServerAnswers() throws {
        let repository: InMemoryAppUserRepository = InMemoryAppUserRepository()
        var user: AppUser = Fixture.user()
        user.coinBalance = 60
        user.coinRevision = 5
        try repository.saveUser(user)
        let fixture: Fixture = Fixture(snapshots: [], repository: repository)
        #expect(fixture.store.balance == 60)
        #expect(fixture.store.revision == 5)
    }

    // MARK: - fixture

    @MainActor
    private struct Fixture {
        let fetcher: FakeAccountFetcher
        let tokenProvider: FakeTokenProvider
        let repository: InMemoryAppUserRepository
        let store: CoinWalletStore

        init(snapshots: [PortalAccountSnapshot], repository: InMemoryAppUserRepository = InMemoryAppUserRepository()) {
            self.fetcher = FakeAccountFetcher(snapshots: snapshots)
            self.tokenProvider = FakeTokenProvider()
            self.repository = repository
            if (try? repository.fetchUser(id: CoinWalletStoreTests.userID.uuidString)) == nil {
                try? repository.saveUser(Self.user())
            }
            self.store = CoinWalletStore(
                accountClient: self.fetcher,
                accessTokenProvider: self.tokenProvider,
                appUserRepository: self.repository,
                activeAppUser: FakeActiveAppUser(currentUserID: CoinWalletStoreTests.userID),
                sleep: { _ in }
            )
        }

        static func snapshot(balance: Int, revision: Int) -> PortalAccountSnapshot {
            return PortalAccountSnapshot(
                userID: CoinWalletStoreTests.userID,
                coinBalance: balance,
                revision: revision,
                pricing: CoinPricing(normal: 100, hard: 300, adReward: 20)
            )
        }

        static func user() -> AppUser {
            let now: Date = Date()
            return AppUser(
                id: CoinWalletStoreTests.userID.uuidString,
                displayName: nil,
                hasRemovedAds: false,
                pendingAdPoints: 0,
                createdAt: now,
                updatedAt: now
            )
        }
    }
}

private final class FakeAccountFetcher: PortalAccountFetching, @unchecked Sendable {
    private var snapshots: [PortalAccountSnapshot]
    private(set) var calls: Int = 0

    init(snapshots: [PortalAccountSnapshot]) {
        self.snapshots = snapshots
    }

    func fetchAccount(accessToken: String) async throws -> PortalAccountSnapshot {
        self.calls += 1
        guard self.snapshots.isEmpty == false else {
            throw PortalAccountClientError.transport
        }
        return self.snapshots.removeFirst()
    }

    func fetchLedger(accessToken: String, cursor: String?) async throws -> CoinLedgerPage {
        throw PortalAccountClientError.transport
    }
}

private final class FakeTokenProvider: PortalAccessTokenProviding, @unchecked Sendable {
    var token: String? = "token"

    func validAccessToken() async -> String? {
        return self.token
    }
}

private struct FakeActiveAppUser: ActiveAppUserProviding {
    let currentUserID: UUID
}

private final class InMemoryAppUserRepository: AppUserRepository, @unchecked Sendable {
    private var users: [String: AppUser] = [:]

    func fetchUser(id: String) throws -> AppUser? {
        return self.users[id]
    }

    func hasProcessedStoreKitTransaction(userID: String, transactionID: String) throws -> Bool {
        return false
    }

    func saveUser(_ user: AppUser) throws {
        self.users[user.id] = user
    }

    func saveUser(_ user: AppUser, storeKitTransaction: UserStoreKitTransaction) throws {
        self.users[user.id] = user
    }

    func saveUser(_ user: AppUser, storeKitTransactions: [UserStoreKitTransaction]) throws {
        self.users[user.id] = user
    }
}
