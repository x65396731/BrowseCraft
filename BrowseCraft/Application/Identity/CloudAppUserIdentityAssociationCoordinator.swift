import Foundation

enum CloudAppUserIdentityAssociationError: Error, Equatable, Sendable {
    /// 中文注释：没有有效的 Portal 会话。云端身份记录只能写后端签发的 AppUser UUID，
    /// 未登录时活动用户是启动器在本机生成的临时 UUID，不得写进 `AppUserIdentity/default`。
    case signInRequired
    case activeUserChanged
    case unexpectedState
}

enum StoreKitPurchaseIdentityAuthorizationError: Error, Equatable, Sendable {
    case signInRequired
    case activeUserChanged
}

/// 中文注释：只有 Feature 的用户主动动作可以调用该协调器；App 生命周期不得自动调用。
/// 关联前先过 Portal 登录门禁（与下方购买授权器同一道检查）：没有有效 Portal 会话就不读、不建云端身份记录。
actor CloudAppUserIdentityAssociationCoordinator {
    private let identityStore: any CloudAppUserIdentityStoring
    private let activeAppUser: any ActiveAppUserProviding
    private let portalSessionCoordinator: PortalSessionCoordinator
    private let appUserRepository: (any AppUserRepository)?
    private let identityOriginStore: (any PortalAppUserIdentityOriginStoring)?
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - appUserRepository / identityOriginStore: 两者都给时才启用「覆盖本机旧本地 UUID」的清理路径；
    ///     任一为 nil 时云端记录与当前用户不一致一律交给用户裁定。
    init(
        identityStore: any CloudAppUserIdentityStoring,
        activeAppUser: any ActiveAppUserProviding,
        portalSessionCoordinator: PortalSessionCoordinator,
        appUserRepository: (any AppUserRepository)? = nil,
        identityOriginStore: (any PortalAppUserIdentityOriginStoring)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.identityStore = identityStore
        self.activeAppUser = activeAppUser
        self.portalSessionCoordinator = portalSessionCoordinator
        self.appUserRepository = appUserRepository
        self.identityOriginStore = identityOriginStore
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
            try await self.requirePortalSignIn(localUserID)

            if let cloudIdentity: CloudAppUserIdentity =
                try await self.identityStore.fetchIdentity() {
                try self.requireActiveUser(localUserID)
                if cloudIdentity.userID != localUserID,
                   try self.isFormerLocalUser(cloudIdentity.userID) {
                    return try await self.replaceFormerLocalIdentity(
                        cloudIdentity,
                        localUserID: localUserID
                    )
                }
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

    /// 中文注释：门禁——当前活动用户必须就是有效 Portal 会话的后端 UUID。
    /// 会话为空是「未登录」；会话用户与活动用户不同是登录切换还没落地，按活动用户已变处理。
    private func requirePortalSignIn(_ localUserID: UUID) async throws {
        guard let portalUserID: UUID =
            await self.portalSessionCoordinator.authenticatedUserID() else {
            CloudSyncDiagnostics.logIdentityAssociation(
                event: "portal-sign-in-required",
                localUserID: localUserID
            )
            throw CloudAppUserIdentityAssociationError.signInRequired
        }
        guard portalUserID == localUserID else {
            throw CloudAppUserIdentityAssociationError.activeUserChanged
        }
    }

    /// 中文注释：清理路径——门禁加上之前，未登录开同步会把本机临时 UUID 写进云端。
    /// 判据：云端那个 UUID 在本机 `app_users` 里有行（本机生成过它），且本机从未见过它作为 Portal 会话用户
    /// （`PortalAppUserIdentityOriginStoring` 没标过）。别的账户的后端 UUID 要么本机没有行，要么登录过就被标过，不会误判。
    private func isFormerLocalUser(_ userID: UUID) throws -> Bool {
        guard let appUserRepository: any AppUserRepository = self.appUserRepository,
              let identityOriginStore: any PortalAppUserIdentityOriginStoring =
                self.identityOriginStore else {
            return false
        }
        guard try appUserRepository.fetchUser(id: userID.uuidString) != nil else {
            return false
        }
        return try identityOriginStore.containsPortalUserID(userID) == false
    }

    private func replaceFormerLocalIdentity(
        _ cloudIdentity: CloudAppUserIdentity,
        localUserID: UUID
    ) async throws -> CloudAppUserIdentityAssociationState {
        CloudSyncDiagnostics.logIdentityAssociation(
            event: "former-local-identity-replace-started",
            localUserID: localUserID,
            cloudUserID: cloudIdentity.userID
        )
        let replacement: CloudAppUserIdentity = CloudAppUserIdentity(
            userID: localUserID,
            schemaVersion: CloudAppUserIdentity.currentSchemaVersion,
            createdAt: cloudIdentity.createdAt,
            updatedAt: self.now()
        )
        let replaced: CloudAppUserIdentity = try await self.identityStore.replaceIdentity(
            replacement,
            replacing: cloudIdentity
        )
        try self.requireActiveUser(localUserID)
        let state: CloudAppUserIdentityAssociationState = Self.resolve(
            localUserID: localUserID,
            cloudIdentity: replaced
        )
        CloudSyncDiagnostics.logIdentityAssociation(
            event: replaced.userID == localUserID
                ? "former-local-identity-replaced"
                : "former-local-identity-replace-conflict",
            localUserID: localUserID,
            cloudUserID: replaced.userID
        )
        return state
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
