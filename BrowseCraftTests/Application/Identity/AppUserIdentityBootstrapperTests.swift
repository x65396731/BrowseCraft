import Foundation
import Testing
@testable import BrowseCraft

struct AppUserIdentityBootstrapperTests {
    @Test func missingIdentityIsSavedBeforeDatabaseUserIsCreated() throws {
        let userID: UUID = try #require(UUID(uuidString: "7125df34-6803-47ef-af12-4ae763b1b806"))
        let events: IdentityBootstrapEvents = IdentityBootstrapEvents()
        let identityStore: MockAppUserIdentityStore = MockAppUserIdentityStore(events: events)
        let repository: IdentityBootstrapAppUserRepository = IdentityBootstrapAppUserRepository(
            events: events
        )
        let now: Date = Date(timeIntervalSince1970: 1_785_000_000)
        let bootstrapper: AppUserIdentityBootstrapper = AppUserIdentityBootstrapper(
            identityStore: identityStore,
            appUserRepository: repository,
            makeUserID: { userID },
            now: { now }
        )

        let result: UUID = try bootstrapper.bootstrap()

        #expect(result == userID)
        #expect(identityStore.userID == userID)
        #expect(repository.user?.id == userID.uuidString)
        #expect(repository.user?.siteSlotLimit == 1)
        #expect(repository.user?.createdAt == now)
        #expect(events.values == ["keychain.save", "database.save"])
    }

    @Test func storedIdentityCreatesMissingDatabaseUserWithoutGeneratingAnotherID() throws {
        let storedUserID: UUID = try #require(
            UUID(uuidString: "1ba2eab7-8e2c-41e5-aafb-22f85794f6fe")
        )
        let identityStore: MockAppUserIdentityStore = MockAppUserIdentityStore(userID: storedUserID)
        let repository: IdentityBootstrapAppUserRepository = IdentityBootstrapAppUserRepository()
        var generatorCallCount: Int = 0
        let bootstrapper: AppUserIdentityBootstrapper = AppUserIdentityBootstrapper(
            identityStore: identityStore,
            appUserRepository: repository,
            makeUserID: {
                generatorCallCount += 1
                return UUID()
            }
        )

        let result: UUID = try bootstrapper.bootstrap()

        #expect(result == storedUserID)
        #expect(generatorCallCount == 0)
        #expect(repository.user?.id == storedUserID.uuidString)
    }

    @Test func existingDatabaseUserIsNotOverwritten() throws {
        let userID: UUID = try #require(UUID(uuidString: "7a9bd1f5-e1a6-4b04-b36a-c952750385c5"))
        let originalDate: Date = Date(timeIntervalSince1970: 1_700_000_000)
        let existingUser: AppUser = AppUser(
            id: userID.uuidString,
            displayName: "Existing",
            hasRemovedAds: true,
            pendingAdPoints: 42,
            siteSlotLimit: 7,
            purchasedSiteSlots: 6,
            createdAt: originalDate,
            updatedAt: originalDate
        )
        let repository: IdentityBootstrapAppUserRepository = IdentityBootstrapAppUserRepository(
            user: existingUser
        )
        let bootstrapper: AppUserIdentityBootstrapper = AppUserIdentityBootstrapper(
            identityStore: MockAppUserIdentityStore(userID: userID),
            appUserRepository: repository
        )

        _ = try bootstrapper.bootstrap()

        #expect(repository.saveCallCount == 0)
        #expect(repository.user == existingUser)
    }

    @Test func databaseFailureKeepsGeneratedIdentityForNextLaunchRetry() throws {
        let userID: UUID = try #require(UUID(uuidString: "632b0056-e14a-407c-bb5e-c51fb46be37e"))
        let identityStore: MockAppUserIdentityStore = MockAppUserIdentityStore()
        let failingRepository: IdentityBootstrapAppUserRepository =
            IdentityBootstrapAppUserRepository(saveError: IdentityBootstrapTestError.databaseWrite)
        let firstBootstrapper: AppUserIdentityBootstrapper = AppUserIdentityBootstrapper(
            identityStore: identityStore,
            appUserRepository: failingRepository,
            makeUserID: { userID }
        )

        #expect(throws: IdentityBootstrapTestError.databaseWrite) {
            try firstBootstrapper.bootstrap()
        }
        #expect(identityStore.userID == userID)

        let retryRepository: IdentityBootstrapAppUserRepository =
            IdentityBootstrapAppUserRepository()
        let retryBootstrapper: AppUserIdentityBootstrapper = AppUserIdentityBootstrapper(
            identityStore: identityStore,
            appUserRepository: retryRepository,
            makeUserID: { UUID() }
        )

        let retryResult: UUID = try retryBootstrapper.bootstrap()

        #expect(retryResult == userID)
        #expect(retryRepository.user?.id == userID.uuidString)
    }

    @Test func activeUserStorePublishesUpdatedIdentity() throws {
        let first: UUID = try #require(UUID(uuidString: "7e46f2b0-0516-474c-bad6-8561999f71e4"))
        let second: UUID = try #require(UUID(uuidString: "cc439366-c780-42e5-bc99-cfa2a8cabbd9"))
        let store: ActiveAppUserStore = ActiveAppUserStore(initialUserID: first)

        #expect(store.currentUserID == first)
        store.update(second)
        #expect(store.currentUserID == second)
    }
}

private final class IdentityBootstrapEvents {
    private(set) var values: [String] = []

    func append(_ value: String) {
        self.values.append(value)
    }
}

private final class MockAppUserIdentityStore: AppUserIdentityStoring, @unchecked Sendable {
    private(set) var userID: UUID?
    private let events: IdentityBootstrapEvents?

    init(userID: UUID? = nil, events: IdentityBootstrapEvents? = nil) {
        self.userID = userID
        self.events = events
    }

    func loadUserID() throws -> UUID? {
        return self.userID
    }

    func saveUserID(_ userID: UUID) throws {
        self.events?.append("keychain.save")
        self.userID = userID
    }
}

private final class IdentityBootstrapAppUserRepository: AppUserRepository {
    private(set) var user: AppUser?
    private(set) var saveCallCount: Int = 0
    private let events: IdentityBootstrapEvents?
    private let saveError: IdentityBootstrapTestError?

    init(
        user: AppUser? = nil,
        events: IdentityBootstrapEvents? = nil,
        saveError: IdentityBootstrapTestError? = nil
    ) {
        self.user = user
        self.events = events
        self.saveError = saveError
    }

    func fetchUser(id: String) throws -> AppUser? {
        guard self.user?.id == id else {
            return nil
        }
        return self.user
    }

    func hasProcessedStoreKitTransaction(userID: String, transactionID: String) throws -> Bool {
        _ = userID
        _ = transactionID
        return false
    }

    func saveUser(_ user: AppUser) throws {
        if let saveError: IdentityBootstrapTestError = self.saveError {
            throw saveError
        }
        self.events?.append("database.save")
        self.saveCallCount += 1
        self.user = user
    }

    func saveUser(_ user: AppUser, storeKitTransaction: UserStoreKitTransaction) throws {
        _ = storeKitTransaction
        try self.saveUser(user)
    }
}

private enum IdentityBootstrapTestError: Error {
    case databaseWrite
}
