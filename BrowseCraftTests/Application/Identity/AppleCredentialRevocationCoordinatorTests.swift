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

    private static func coordinator(
        state: AppleCredentialState,
        storedIdentifier: String?,
        isSignedIn: Bool,
        probe: SignOutProbe
    ) -> AppleCredentialRevocationCoordinator {
        return AppleCredentialRevocationCoordinator(
            checker: StubCredentialStateChecker(state: state),
            userIdentifierStore: StubAppleUserIdentifierStore(identifier: storedIdentifier),
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
    let state: AppleCredentialState
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

private struct StubAppleUserIdentifierStore: AppleUserIdentifierStoring {
    let identifier: String?

    func loadUserIdentifier() throws -> String? {
        return self.identifier
    }

    func saveUserIdentifier(_ userIdentifier: String) throws {}

    func clearUserIdentifier() throws {}
}
