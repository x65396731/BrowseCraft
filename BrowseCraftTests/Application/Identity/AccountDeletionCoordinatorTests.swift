import Foundation
import Testing
@testable import BrowseCraft

/// docs/design/Account-Deletion-Design.md 第四–七节：删号流程、先换身份再删旧数据、iCloud 待清与续做。
@MainActor
struct AccountDeletionCoordinatorTests {
    private let deletedUserID: UUID = UUID()
    private let guestUserID: UUID = UUID()

    // MARK: - 主流程

    @Test func successSwitchesToGuestBeforeDeletingOldDataAndClearsEverything() async throws {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)

        let outcome: AccountDeletionOutcome = try await harness.coordinator.deleteAccount()

        #expect(outcome == AccountDeletionOutcome(appleRevocationFailed: false, localCleanup: .done, cloudCleanup: .done))
        #expect(harness.activeAppUser.currentUserID == self.guestUserID)
        #expect(harness.guestProvisioner.provisionCount == 1)
        #expect(harness.localStore.deletedUserIDs == [self.deletedUserID])
        // 中文注释：旧用户被删时它已经不是活动用户。
        #expect(harness.localStore.activeUserAtDeletion == [self.guestUserID])
        #expect(harness.bookFiles.removedPaths == ["a.epub", "a.cover"])
        #expect(await harness.cloudEraser.erasedUserIDs == [self.deletedUserID])
        #expect(await harness.cloudEraser.lastScopes == [CloudAccountScope.cloud(hash: "a")])
        #expect(await harness.session.discardCount == 2)
        #expect(harness.appleUserIdentifierStore.identifier == nil)
        #expect(harness.pendingStore.work.isEmpty)
        #expect(harness.events == ["prepare", "reset-identity"])
        let request: FakeDeletionService.Request = try #require(await harness.service.requests.first)
        #expect(request == FakeDeletionService.Request(
            accessToken: "access",
            identityToken: "identity",
            nonce: "nonce",
            authorizationCode: "code"
        ))
    }

    @Test func revokeFailedIsReportedOnCompletion() async throws {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        await harness.service.setResult(.success(AccountDeletionServerResult(appleRevocationFailed: true)))

        let outcome: AccountDeletionOutcome = try await harness.coordinator.deleteAccount()

        #expect(outcome.appleRevocationFailed)
        #expect(harness.activeAppUser.currentUserID == self.guestUserID)
    }

    @Test func cancelledReauthenticationDoesNothing() async {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        harness.authorizer.result = .failure(AppleSignInAuthorizationError.cancelled)

        await #expect(throws: AccountDeletionError.reauthenticationCancelled) {
            _ = try await harness.coordinator.deleteAccount()
        }
        #expect(await harness.service.requests.isEmpty)
        #expect(harness.activeAppUser.currentUserID == self.deletedUserID)
        #expect(harness.pendingStore.work.isEmpty)
    }

    @Test func missingSessionFailsBeforeAskingApple() async {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        await harness.session.setAccessToken(nil)

        await #expect(throws: AccountDeletionError.sessionExpired) {
            _ = try await harness.coordinator.deleteAccount()
        }
        #expect(harness.authorizer.callCount == 0)
    }

    @Test func serverRejectionKeepsAccountAndClearsInFlightMarker() async {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        await harness.service.setResult(.failure(AccountDeletionServiceError.appleAccountMismatch))

        await #expect(throws: AccountDeletionError.appleAccountMismatch) {
            _ = try await harness.coordinator.deleteAccount()
        }
        #expect(harness.activeAppUser.currentUserID == self.deletedUserID)
        #expect(harness.localStore.deletedUserIDs.isEmpty)
        #expect(harness.pendingStore.work.isEmpty)
        #expect(await harness.session.discardCount == 0)
    }

    // MARK: - 结果未知（第七节）

    @Test func unknownOutcomeConfirmedDeletedByProbeCompletesCleanup() async throws {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        await harness.service.setResult(.failure(AccountDeletionServiceError.outcomeUnknown))
        await harness.service.setProbe(.deleted)

        let outcome: AccountDeletionOutcome = try await harness.coordinator.deleteAccount()

        #expect(outcome.localCleanup == .done)
        #expect(harness.activeAppUser.currentUserID == self.guestUserID)
        #expect(harness.pendingStore.work.isEmpty)
    }

    @Test func unknownOutcomeKeepsInFlightMarkerThenResumeSeesAccountStillExists() async {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        await harness.service.setResult(.failure(AccountDeletionServiceError.outcomeUnknown))
        await harness.service.setProbe(.unknown)

        await #expect(throws: AccountDeletionError.outcomeUnknown) {
            _ = try await harness.coordinator.deleteAccount()
        }
        #expect(harness.pendingStore.work.inFlightUserID == self.deletedUserID)

        await harness.service.setProbe(.exists)
        await harness.coordinator.resumePendingWork()

        #expect(harness.pendingStore.work.isEmpty)
        #expect(harness.activeAppUser.currentUserID == self.deletedUserID)
        #expect(harness.localStore.deletedUserIDs.isEmpty)
    }

    @Test func resumeTreatsRejectedSessionAsDeletedAccount() async {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        harness.pendingStore.work.inFlightUserID = self.deletedUserID
        await harness.session.setAccessToken(nil)
        await harness.session.setStatus(.signedOut)

        await harness.coordinator.resumePendingWork()

        #expect(harness.activeAppUser.currentUserID == self.guestUserID)
        #expect(harness.localStore.deletedUserIDs == [self.deletedUserID])
        #expect(harness.pendingStore.work.isEmpty)
    }

    @Test func resumeLeavesInFlightMarkerWhileSessionIsOnlyUnreachable() async {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        harness.pendingStore.work.inFlightUserID = self.deletedUserID
        await harness.session.setAccessToken(nil)
        await harness.session.setStatus(.temporarilyUnavailable)

        await harness.coordinator.resumePendingWork()

        #expect(harness.pendingStore.work.inFlightUserID == self.deletedUserID)
        #expect(harness.activeAppUser.currentUserID == self.deletedUserID)
    }

    // MARK: - 收尾失败与续做（第五、六节）

    @Test func unavailableICloudLeavesPendingMarkerUntilResumeSucceeds() async throws {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        await harness.cloudEraser.enqueue(.failure(AccountDeletionCloudErasureError.accountUnavailable))

        let outcome: AccountDeletionOutcome = try await harness.coordinator.deleteAccount()

        #expect(outcome.cloudCleanup == .pending)
        #expect(outcome.localCleanup == .done)
        #expect(harness.pendingStore.work.cloudCleanups.map(\.userID) == [self.deletedUserID])

        await harness.coordinator.resumePendingWork()

        #expect(harness.pendingStore.work.isEmpty)
        #expect(await harness.cloudEraser.erasedUserIDs == [self.deletedUserID])
    }

    @Test func iCloudOwnedByAnotherAccountIsLeftAloneAndMarkerCleared() async throws {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        await harness.cloudEraser.enqueue(.success(.notOwned))

        let outcome: AccountDeletionOutcome = try await harness.coordinator.deleteAccount()

        #expect(outcome.cloudCleanup == .done)
        #expect(harness.pendingStore.work.isEmpty)
    }

    @Test func localCleanupFailureRetriesAndAsksForReinstallOnThirdFailure() async throws {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        harness.localStore.remainingFailures = 3

        let outcome: AccountDeletionOutcome = try await harness.coordinator.deleteAccount()
        #expect(outcome.localCleanup == .pending)
        // 中文注释：身份已经换掉，旧数据留给续做。
        #expect(harness.activeAppUser.currentUserID == self.guestUserID)
        #expect(harness.pendingStore.work.localCleanupUserIDs == [self.deletedUserID])

        await harness.coordinator.resumePendingWork()
        #expect(harness.pendingStore.work.localCleanupFailureCount == 2)
        await harness.coordinator.resumePendingWork()
        #expect(harness.pendingStore.work.localCleanupFailureCount == 3)
        await harness.coordinator.resumePendingWork()

        #expect(harness.pendingStore.work.isEmpty)
        #expect(harness.localStore.deletedUserIDs == [self.deletedUserID])
        #expect(harness.guestProvisioner.provisionCount == 1)
    }

    @Test func thirdConsecutiveLocalFailureReportsReinstall() async throws {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        harness.localStore.remainingFailures = 10
        harness.pendingStore.work.localCleanupFailureCount = 2

        let outcome: AccountDeletionOutcome = try await harness.coordinator.deleteAccount()

        #expect(outcome.localCleanup == .reinstallRequired)
    }

    @Test func guestProvisioningFailureKeepsDeletedUserActiveAndRetriesSwitchOnResume() async throws {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)
        harness.guestProvisioner.remainingFailures = 1

        let outcome: AccountDeletionOutcome = try await harness.coordinator.deleteAccount()
        #expect(outcome.localCleanup == .pending)
        #expect(harness.activeAppUser.currentUserID == self.deletedUserID)
        // 中文注释：没换成身份就不能删活动用户的行。
        #expect(harness.localStore.deletedUserIDs.isEmpty)

        await harness.coordinator.resumePendingWork()

        #expect(harness.activeAppUser.currentUserID == self.guestUserID)
        #expect(harness.localStore.deletedUserIDs == [self.deletedUserID])
        #expect(harness.pendingStore.work.isEmpty)
    }

    @Test func resumeWithNothingPendingTouchesNothing() async {
        let harness: Harness = Harness(deletedUserID: self.deletedUserID, guestUserID: self.guestUserID)

        await harness.coordinator.resumePendingWork()

        #expect(await harness.service.probeCount == 0)
        #expect(harness.localStore.deletedUserIDs.isEmpty)
        #expect(await harness.cloudEraser.erasedUserIDs.isEmpty)
    }

    // MARK: - iCloud 归属（第 6.1 节）

    @Test func cloudOwnershipFollowsIdentityRecordThenLocalAttestation() {
        let deleted: UUID = UUID()
        let scope: CloudAccountScope = .cloud(hash: "a")
        #expect(AccountDeletionCloudOwnership.isOwned(
            identityUserID: deleted, deletedUserID: deleted, currentScope: scope, associatedScopes: []
        ))
        #expect(AccountDeletionCloudOwnership.isOwned(
            identityUserID: UUID(), deletedUserID: deleted, currentScope: scope, associatedScopes: [scope]
        ) == false)
        #expect(AccountDeletionCloudOwnership.isOwned(
            identityUserID: nil, deletedUserID: deleted, currentScope: scope, associatedScopes: [scope]
        ))
        #expect(AccountDeletionCloudOwnership.isOwned(
            identityUserID: nil, deletedUserID: deleted, currentScope: scope, associatedScopes: [.cloud(hash: "b")]
        ) == false)
    }
}

// MARK: - 测试替身

@MainActor
private final class Harness {
    let activeAppUser: ActiveAppUserStore
    let session: FakeAccountDeletionSession = FakeAccountDeletionSession()
    let authorizer: FakeAppleSignInAuthorizer = FakeAppleSignInAuthorizer()
    let service: FakeDeletionService = FakeDeletionService()
    let guestProvisioner: FakeGuestProvisioner
    let localStore: FakeLocalDataStore
    let bookFiles: FakeBookFileStore = FakeBookFileStore()
    let cloudEraser: FakeCloudEraser = FakeCloudEraser()
    let pendingStore: InMemoryPendingWorkStore = InMemoryPendingWorkStore()
    let appleUserIdentifierStore: InMemoryAppleUserIdentifierStore = InMemoryAppleUserIdentifierStore()
    var events: [String] = []
    private(set) var coordinator: AccountDeletionCoordinator!

    init(deletedUserID: UUID, guestUserID: UUID) {
        let activeAppUser: ActiveAppUserStore = ActiveAppUserStore(initialUserID: deletedUserID)
        self.activeAppUser = activeAppUser
        self.guestProvisioner = FakeGuestProvisioner(guestUserID: guestUserID)
        self.localStore = FakeLocalDataStore(activeAppUser: activeAppUser)
        self.appleUserIdentifierStore.identifier = "apple-user"
        self.coordinator = AccountDeletionCoordinator(
            activeAppUser: self.activeAppUser,
            session: self.session,
            appleAuthorizer: self.authorizer,
            deletionService: self.service,
            guestProvisioner: self.guestProvisioner,
            localDataStore: self.localStore,
            bookFileStore: self.bookFiles,
            cloudEraser: self.cloudEraser,
            pendingWorkStore: self.pendingStore,
            appleUserIdentifierStore: self.appleUserIdentifierStore,
            prepareForIdentityChange: { [weak self] in
                self?.events.append("prepare")
            },
            didResetIdentity: { [weak self] in
                self?.events.append("reset-identity")
            }
        )
    }
}

private actor FakeAccountDeletionSession: AccountDeletionSessionControlling {
    private var accessToken: String? = "access"
    private var status: PortalSessionStatus = .authenticated
    private(set) var discardCount: Int = 0

    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    func setStatus(_ status: PortalSessionStatus) {
        self.status = status
    }

    func issueAppleChallenge() async throws -> PortalAppleAuthenticationChallenge {
        return PortalAppleAuthenticationChallenge(nonce: "nonce", expiresAt: Date().addingTimeInterval(300))
    }

    func validAccessToken() async -> String? {
        return self.accessToken
    }

    func snapshot() async -> PortalSessionSnapshot {
        return PortalSessionSnapshot(status: self.status, userID: UUID(), accessTokenExpiresAt: nil, refreshTokenExpiresAt: nil)
    }

    func discardLocalSessionForDeletedAccount() async {
        self.discardCount += 1
    }
}

@MainActor
private final class FakeAppleSignInAuthorizer: AppleSignInAuthorizing {
    var result: Result<AppleSignInAuthorization, any Error> = .success(
        AppleSignInAuthorization(identityToken: "identity", authorizationCode: "code", userIdentifier: "apple-user")
    )
    private(set) var callCount: Int = 0

    func authorize(nonce: String) async throws -> AppleSignInAuthorization {
        self.callCount += 1
        return try self.result.get()
    }
}

private actor FakeDeletionService: PortalAccountDeleting {
    struct Request: Equatable {
        let accessToken: String
        let identityToken: String
        let nonce: String
        let authorizationCode: String
    }

    private var result: Result<AccountDeletionServerResult, any Error> =
        .success(AccountDeletionServerResult(appleRevocationFailed: false))
    private var probe: AccountDeletionProbeResult = .unknown
    private(set) var requests: [Request] = []
    private(set) var probeCount: Int = 0

    func setResult(_ result: Result<AccountDeletionServerResult, any Error>) {
        self.result = result
    }

    func setProbe(_ probe: AccountDeletionProbeResult) {
        self.probe = probe
    }

    func deleteAccount(
        accessToken: String,
        identityToken: String,
        nonce: String,
        authorizationCode: String
    ) async throws -> AccountDeletionServerResult {
        self.requests.append(Request(
            accessToken: accessToken,
            identityToken: identityToken,
            nonce: nonce,
            authorizationCode: authorizationCode
        ))
        return try self.result.get()
    }

    func probeAccount(accessToken: String) async -> AccountDeletionProbeResult {
        self.probeCount += 1
        return self.probe
    }
}

private final class FakeGuestProvisioner: GuestIdentityProvisioning {
    let guestUserID: UUID
    var remainingFailures: Int = 0
    private(set) var provisionCount: Int = 0

    init(guestUserID: UUID) {
        self.guestUserID = guestUserID
    }

    func provisionNewGuest() throws -> UUID {
        if self.remainingFailures > 0 {
            self.remainingFailures -= 1
            throw KeychainAppUserIdentityStoreError.unexpectedStatus(-34018)
        }
        self.provisionCount += 1
        return self.guestUserID
    }
}

private enum FakeLocalFailure: Error {
    case database
}

private final class FakeLocalDataStore: AccountDeletionLocalDataStoring, @unchecked Sendable {
    private let activeAppUser: ActiveAppUserStore
    var remainingFailures: Int = 0
    private(set) var deletedUserIDs: [UUID] = []
    private(set) var activeUserAtDeletion: [UUID] = []

    init(activeAppUser: ActiveAppUserStore) {
        self.activeAppUser = activeAppUser
    }

    func associatedCloudScopes(for userID: UUID) throws -> [CloudAccountScope] {
        return [.cloud(hash: "a")]
    }

    func deleteLocalData(for userID: UUID) throws -> [String] {
        if self.remainingFailures > 0 {
            self.remainingFailures -= 1
            throw FakeLocalFailure.database
        }
        self.deletedUserIDs.append(userID)
        self.activeUserAtDeletion.append(self.activeAppUser.currentUserID)
        return ["a.epub", "a.cover"]
    }
}

private final class FakeBookFileStore: BookFileStoring, @unchecked Sendable {
    private(set) var removedPaths: [String] = []

    func storeBookFile(from sourceURL: URL, bookID: UUID, fileExtension: String) async throws -> StoredBookFile {
        return StoredBookFile(relativePath: "", sha256: "", byteCount: 0)
    }

    func storeCover(_ data: Data, bookID: UUID) async throws -> String {
        return ""
    }

    func removeFile(relativePath: String) async throws {
        self.removedPaths.append(relativePath)
    }

    func fileURL(relativePath: String) -> URL {
        return URL(fileURLWithPath: "/tmp/\(relativePath)")
    }
}

private actor FakeCloudEraser: AccountDeletionCloudDataErasing {
    private var queued: [Result<AccountDeletionCloudErasure, any Error>] = []
    private(set) var erasedUserIDs: [UUID] = []
    private(set) var lastScopes: [CloudAccountScope] = []

    func enqueue(_ result: Result<AccountDeletionCloudErasure, any Error>) {
        self.queued.append(result)
    }

    func eraseCloudData(
        for userID: UUID,
        associatedScopes: [CloudAccountScope]
    ) async throws -> AccountDeletionCloudErasure {
        self.lastScopes = associatedScopes
        let result: Result<AccountDeletionCloudErasure, any Error> =
            self.queued.isEmpty ? .success(.erased) : self.queued.removeFirst()
        let erasure: AccountDeletionCloudErasure = try result.get()
        self.erasedUserIDs.append(userID)
        return erasure
    }
}

private final class InMemoryPendingWorkStore: AccountDeletionPendingWorkStoring, @unchecked Sendable {
    var work: AccountDeletionPendingWork = AccountDeletionPendingWork()

    func load() -> AccountDeletionPendingWork {
        return self.work
    }

    func save(_ work: AccountDeletionPendingWork) {
        self.work = work
    }
}

private final class InMemoryAppleUserIdentifierStore: AppleUserIdentifierStoring, @unchecked Sendable {
    var identifier: String?

    func loadUserIdentifier() throws -> String? {
        return self.identifier
    }

    func lastAuthorizedAt() throws -> Date? {
        return nil
    }

    func hasObservedAuthorized() throws -> Bool {
        return false
    }

    func markObservedAuthorized() throws {}

    func saveUserIdentifier(_ userIdentifier: String) throws {
        self.identifier = userIdentifier
    }

    func clearUserIdentifier() throws {
        self.identifier = nil
    }
}
