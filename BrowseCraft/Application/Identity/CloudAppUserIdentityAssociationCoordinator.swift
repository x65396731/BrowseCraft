import Foundation

enum CloudAppUserIdentityAssociationError: Error, Equatable, Sendable {
    case activeUserChanged
    case unexpectedState
}

enum StoreKitPurchaseIdentityAuthorizationError: Error, Equatable, Sendable {
    case signInRequired
    case activeUserChanged
}

/// 中文注释：只有 Feature 的用户主动动作可以调用该协调器；App 生命周期不得自动调用。
actor CloudAppUserIdentityAssociationCoordinator {
    private let identityStore: any CloudAppUserIdentityStoring
    private let activeAppUser: any ActiveAppUserProviding
    private let now: @Sendable () -> Date

    init(
        identityStore: any CloudAppUserIdentityStoring,
        activeAppUser: any ActiveAppUserProviding,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.identityStore = identityStore
        self.activeAppUser = activeAppUser
        self.now = now
    }

    func associateForUserInitiatedAccess() async throws
        -> CloudAppUserIdentityAssociationState {
        let localUserID: UUID = self.activeAppUser.currentUserID
        CloudSyncDiagnostics.logIdentityAssociation(
            event: "manual-link-started",
            localUserID: localUserID
        )

        do {
            if let cloudIdentity: CloudAppUserIdentity =
                try await self.identityStore.fetchIdentity() {
                try self.requireActiveUser(localUserID)
                let state: CloudAppUserIdentityAssociationState = Self.resolve(
                    localUserID: localUserID,
                    cloudIdentity: cloudIdentity
                )
                CloudSyncDiagnostics.logIdentityAssociation(
                    event: cloudIdentity.userID == localUserID
                        ? "existing-identity-matched"
                        : "existing-identity-conflict",
                    localUserID: localUserID,
                    cloudUserID: cloudIdentity.userID
                )
                return state
            }

            try self.requireActiveUser(localUserID)
            CloudSyncDiagnostics.logIdentityAssociation(
                event: "identity-create-started",
                localUserID: localUserID
            )
            let proposedIdentity: CloudAppUserIdentity = .proposed(
                userID: localUserID,
                at: self.now()
            )
            let cloudIdentity: CloudAppUserIdentity = try await self.identityStore
                .createIdentityIfAbsent(proposedIdentity)
            try self.requireActiveUser(localUserID)
            let state: CloudAppUserIdentityAssociationState = Self.resolve(
                localUserID: localUserID,
                cloudIdentity: cloudIdentity
            )
            CloudSyncDiagnostics.logIdentityAssociation(
                event: cloudIdentity.userID == localUserID
                    ? "identity-created"
                    : "create-race-conflict",
                localUserID: localUserID,
                cloudUserID: cloudIdentity.userID
            )
            return state
        } catch {
            CloudSyncDiagnostics.logIdentityAssociationFailed(
                stage: "manual-link",
                error: error
            )
            throw error
        }
    }

    private func requireActiveUser(_ expectedUserID: UUID) throws {
        guard self.activeAppUser.currentUserID == expectedUserID else {
            throw CloudAppUserIdentityAssociationError.activeUserChanged
        }
    }

    private static func resolve(
        localUserID: UUID,
        cloudIdentity: CloudAppUserIdentity
    ) -> CloudAppUserIdentityAssociationState {
        guard cloudIdentity.userID == localUserID else {
            return .requiresUserDecision(
                localUserID: localUserID,
                cloudIdentity: cloudIdentity
            )
        }
        return .associated(identity: cloudIdentity)
    }
}

/// 中文注释：购买和恢复只接受当前 Portal Session 的后端 AppUser UUID，iCloud 不参与授权。
actor StoreKitPurchaseIdentityAuthorizer {
    private let activeAppUser: any ActiveAppUserProviding
    private let portalSessionCoordinator: PortalSessionCoordinator
    private let appleSignInCoordinator: PortalAppleSignInCoordinator

    init(
        activeAppUser: any ActiveAppUserProviding,
        portalSessionCoordinator: PortalSessionCoordinator,
        appleSignInCoordinator: PortalAppleSignInCoordinator
    ) {
        self.activeAppUser = activeAppUser
        self.portalSessionCoordinator = portalSessionCoordinator
        self.appleSignInCoordinator = appleSignInCoordinator
    }

    /// 中文注释：仅由用户点击购买或恢复按钮触发，成功返回的 UUID 可安全传给 appAccountToken。
    func authorizeUserInitiatedStoreKitAction() async throws -> UUID {
        var localUserID: UUID = self.activeAppUser.currentUserID
        IAPDiagnostics.notice(
            "event=identity-authorization-started " +
                "userHash=\(IAPDiagnostics.hash(localUserID))"
        )
        var portalUserID: UUID? =
            await self.portalSessionCoordinator.authenticatedUserID()
        if portalUserID == nil {
            do {
                _ = try await self.appleSignInCoordinator.signIn()
            } catch let error as AppleSignInAuthorizationError
                where error == .cancelled {
                throw StoreKitPurchaseIdentityAuthorizationError.signInRequired
            }
            localUserID = self.activeAppUser.currentUserID
            portalUserID = await self.portalSessionCoordinator.authenticatedUserID()
        }
        guard let portalUserID else {
            throw StoreKitPurchaseIdentityAuthorizationError.signInRequired
        }

        try self.requireActiveUser(localUserID)
        guard portalUserID == localUserID else {
            IAPDiagnostics.error(
                "event=identity-authorization-failed " +
                    "reason=portal-account-mismatch"
            )
            throw StoreKitPurchaseIdentityAuthorizationError.activeUserChanged
        }
        IAPDiagnostics.notice(
            "event=identity-authorization-succeeded " +
                "userHash=\(IAPDiagnostics.hash(localUserID))"
        )
        return localUserID
    }

    /// 中文注释：StoreKit 系统购买面板返回后，再确认等待期间活动 UUID 没有被切换。
    func validateAuthorizedUser(_ expectedUserID: UUID) throws {
        try self.requireActiveUser(expectedUserID)
    }

    private func requireActiveUser(_ expectedUserID: UUID) throws {
        guard self.activeAppUser.currentUserID == expectedUserID else {
            IAPDiagnostics.error(
                "event=identity-authorization-failed reason=active-user-changed"
            )
            throw StoreKitPurchaseIdentityAuthorizationError.activeUserChanged
        }
    }
}
