import Foundation
import Testing
@testable import BrowseCraft

/// docs/design/Account-Deletion-Design.md 第十节：revoked / notFound 按退出登录处理，其余不动；没存 Apple user 或没登录就不查。
@MainActor
struct AppleCredentialRevocationCoordinatorTests {
    @Test(arguments: [
        (AppleCredentialState.revoked, 1),
        (AppleCredentialState.notFound, 1),
        (AppleCredentialState.authorized, 0),
        (AppleCredentialState.transferred, 0),
        (AppleCredentialState.unknown, 0)
    ])
    func signsOutOnlyForRevokedOrNotFound(state: AppleCredentialState, expectedSignOuts: Int) async {
        let probe: SignOutProbe = SignOutProbe()
        let coordinator: AppleCredentialRevocationCoordinator = Self.coordinator(
            state: state,
            storedIdentifier: "apple-user",
            isSignedIn: true,
            probe: probe
        )

        await coordinator.checkCredentialState()

        #expect(probe.signOutCount == expectedSignOuts)
    }

    @Test func skipsWhenSignedOutOrIdentifierMissing() async {
        let signedOutProbe: SignOutProbe = SignOutProbe()
        await Self.coordinator(state: .revoked, storedIdentifier: "apple-user", isSignedIn: false, probe: signedOutProbe)
            .checkCredentialState()
        let missingProbe: SignOutProbe = SignOutProbe()
        let missingChecker: StubCredentialStateChecker = StubCredentialStateChecker(state: .revoked)
        await AppleCredentialRevocationCoordinator(
            checker: missingChecker,
            userIdentifierStore: StubAppleUserIdentifierStore(identifier: nil),
            isSignedIn: { true },
            signOut: { missingProbe.signOutCount += 1 }
        ).checkCredentialState()

        #expect(signedOutProbe.signOutCount == 0)
        #expect(missingProbe.signOutCount == 0)
        #expect(missingChecker.queriedIdentifiers.isEmpty)
    }

    /// 中文注释：模拟器实测——撤销后重新登录，系统一直回 revoked：没见过 authorized 之前的 revoked 一律不作数；
    /// 见过 authorized 之后再回 revoked 才退出。
    @Test func revokedBeforeAnyAuthorizedObservationIsIgnoredAfterwardsSignsOut() async {
        let store: StubAppleUserIdentifierStore = StubAppleUserIdentifierStore(identifier: "apple-user")
        let checker: StubCredentialStateChecker = StubCredentialStateChecker(state: .revoked)
        let probe: SignOutProbe = SignOutProbe()
        var refreshCount: Int = 0
        let coordinator: AppleCredentialRevocationCoordinator = AppleCredentialRevocationCoordinator(
            checker: checker,
            userIdentifierStore: store,
            isSignedIn: { true },
            signOut: { probe.signOutCount += 1 }
        )
        coordinator.didSignOut = { refreshCount += 1 }

        await coordinator.checkCredentialState()
        await coordinator.checkCredentialState()
        #expect(probe.signOutCount == 0)

        checker.state = .authorized
        await coordinator.checkCredentialState()
        #expect(store.observedAuthorized)

        checker.state = .revoked
        await coordinator.checkCredentialState()
        #expect(probe.signOutCount == 1)
        #expect(refreshCount == 1)
    }

    @Test func newAuthorizationResetsObservation() throws {
        let store: StubAppleUserIdentifierStore = StubAppleUserIdentifierStore(identifier: "apple-user", observedAuthorized: true)
        try store.saveUserIdentifier("apple-user")
        #expect(try store.hasObservedAuthorized() == false)
    }

    private static func coordinator(
        state: AppleCredentialState,
        storedIdentifier: String?,
        isSignedIn: Bool,
        probe: SignOutProbe
    ) -> AppleCredentialRevocationCoordinator {
        return AppleCredentialRevocationCoordinator(
            checker: StubCredentialStateChecker(state: state),
            userIdentifierStore: StubAppleUserIdentifierStore(identifier: storedIdentifier, observedAuthorized: true),
            isSignedIn: { isSignedIn },
            signOut: { probe.signOutCount += 1 }
        )
    }
}

@MainActor
private final class SignOutProbe {
    var signOutCount: Int = 0
}

private final class StubCredentialStateChecker: AppleCredentialStateChecking, @unchecked Sendable {
    var state: AppleCredentialState
    private(set) var queriedIdentifiers: [String] = []

    init(state: AppleCredentialState) {
        self.state = state
    }

    func credentialState(forUserIdentifier userIdentifier: String) async -> AppleCredentialState {
        self.queriedIdentifiers.append(userIdentifier)
        return self.state
    }

    func revocationNotifications() -> AsyncStream<Void> {
        return AsyncStream { $0.finish() }
    }
}

private final class StubAppleUserIdentifierStore: AppleUserIdentifierStoring, @unchecked Sendable {
    var identifier: String?
    var observedAuthorized: Bool

    init(identifier: String?, observedAuthorized: Bool = false) {
        self.identifier = identifier
        self.observedAuthorized = observedAuthorized
    }

    func loadUserIdentifier() throws -> String? {
        return self.identifier
    }

    func lastAuthorizedAt() throws -> Date? {
        return nil
    }

    func hasObservedAuthorized() throws -> Bool {
        return self.observedAuthorized
    }

    func markObservedAuthorized() throws {
        self.observedAuthorized = true
    }

    func saveUserIdentifier(_ userIdentifier: String) throws {
        self.identifier = userIdentifier
        self.observedAuthorized = false
    }

    func clearUserIdentifier() throws {
        self.identifier = nil
    }
}
