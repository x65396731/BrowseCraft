import Foundation

enum AppUserIdentityAdoptionError: Error, Equatable, Sendable {
    case invalidCloudIdentity
    case activeUserChanged
    case portalSessionResetFailed
    case identityRollbackFailed
}

/// 中文注释：采用后端签发的 Portal UUID；仅访客首次登录可迁移本地内容，账户间切换始终隔离数据。
actor AppUserIdentityAdoptionCoordinator {
    private let adoptionStore: any AppUserIdentityAdoptionStoring
    private let identityStore: any AppUserIdentityStoring
    private let activeAppUser: ActiveAppUserStore
    private let portalSessionCoordinator: PortalSessionCoordinator
    private let cloudSyncCoordinator: CloudSyncCoordinator?

    init(
        adoptionStore: any AppUserIdentityAdoptionStoring,
        identityStore: any AppUserIdentityStoring,
        activeAppUser: ActiveAppUserStore,
        portalSessionCoordinator: PortalSessionCoordinator,
        cloudSyncCoordinator: CloudSyncCoordinator? = nil
    ) {
        self.adoptionStore = adoptionStore
        self.identityStore = identityStore
        self.activeAppUser = activeAppUser
        self.portalSessionCoordinator = portalSessionCoordinator
        self.cloudSyncCoordinator = cloudSyncCoordinator
    }

    func localDataSummary(
        for expectedUserID: UUID
    ) throws -> AppUserIdentityLocalDataSummary {
        try self.requireActiveUser(expectedUserID)
        return try self.adoptionStore.summary(for: expectedUserID)
    }

    /// 中文注释：Apple 登录成功后采用后端 AppUser UUID；decision 决定是否迁移访客内容，权益和交易永不复制。
    func adoptAuthenticatedPortalUser(
        localUserID: UUID,
        portalUserID: UUID,
        decision: CloudAccountLocalDataDecision,
        sessionTransitionID: UUID
    ) async throws -> AppUserIdentityAdoptionResult {
        guard localUserID != portalUserID else {
            return AppUserIdentityAdoptionResult(
                copiedSourceCount: 0,
                copiedFavoriteItemCount: 0,
                copiedHistoryCount: 0,
                copiedTemporaryResourceCount: 0,
                copiedLibraryState: false
            )
        }
        let portalIdentity: CloudAppUserIdentity = CloudAppUserIdentity.proposed(
            userID: portalUserID,
            at: Date()
        )
        return try await self.performAdoption(
            localUserID: localUserID,
            cloudIdentity: portalIdentity,
            decision: decision,
            sessionTransitionID: sessionTransitionID
        )
    }

    private func performAdoption(
        localUserID: UUID,
        cloudIdentity: CloudAppUserIdentity,
        decision: CloudAccountLocalDataDecision,
        sessionTransitionID: UUID
    ) async throws -> AppUserIdentityAdoptionResult {
        CloudSyncDiagnostics.logIdentityAssociation(
            event: "adoption-started-\(decision.rawValue)",
            localUserID: localUserID,
            cloudUserID: cloudIdentity.userID
        )
        guard cloudIdentity.usesSupportedSchema,
              cloudIdentity.userID != localUserID else {
            CloudSyncDiagnostics.logIdentityAssociationFailed(
                stage: "adoption-validation",
                error: AppUserIdentityAdoptionError.invalidCloudIdentity
            )
            throw AppUserIdentityAdoptionError.invalidCloudIdentity
        }
        try self.requireActiveUser(localUserID)
        await self.cloudSyncCoordinator?.prepareForIdentityChange()
        try self.requireActiveUser(localUserID)

        let result: AppUserIdentityAdoptionResult = try self.adoptionStore
            .prepareAdoption(
                from: localUserID,
                to: cloudIdentity.userID,
                decision: decision
            )
        CloudSyncDiagnostics.logIdentityAssociation(
            event: "adoption-data-prepared",
            localUserID: localUserID,
            cloudUserID: cloudIdentity.userID
        )
        try self.requireActiveUser(localUserID)

        try self.identityStore.saveUserID(cloudIdentity.userID)
        CloudSyncDiagnostics.logIdentityAssociation(
            event: "adoption-keychain-updated",
            localUserID: localUserID,
            cloudUserID: cloudIdentity.userID
        )
        guard self.activeAppUser.currentUserID == localUserID else {
            do {
                try self.identityStore.saveUserID(localUserID)
            } catch {
                throw AppUserIdentityAdoptionError.identityRollbackFailed
            }
            throw AppUserIdentityAdoptionError.activeUserChanged
        }

        self.activeAppUser.update(cloudIdentity.userID)
        CloudSyncDiagnostics.logIdentityAssociation(
            event: "adoption-active-user-updated",
            localUserID: localUserID,
            cloudUserID: cloudIdentity.userID
        )
        do {
            try await self.portalSessionCoordinator
                .commitAuthenticatedSessionTransition(sessionTransitionID)
        } catch {
            do {
                try self.identityStore.saveUserID(localUserID)
                self.activeAppUser.update(localUserID)
            } catch {
                // 中文注释：回滚失败时保持内存与已经写入的 B 一致；旧 A Portal token 仍会被 UUID 校验阻断。
                throw AppUserIdentityAdoptionError.identityRollbackFailed
            }
            throw AppUserIdentityAdoptionError.portalSessionResetFailed
        }

        CloudSyncDiagnostics.logIdentityAssociation(
            event: "adoption-completed",
            localUserID: localUserID,
            cloudUserID: cloudIdentity.userID
        )
        return result
    }

    private func requireActiveUser(_ expectedUserID: UUID) throws {
        guard self.activeAppUser.currentUserID == expectedUserID else {
            CloudSyncDiagnostics.logIdentityAssociationFailed(
                stage: "adoption-active-user-check",
                error: AppUserIdentityAdoptionError.activeUserChanged
            )
            throw AppUserIdentityAdoptionError.activeUserChanged
        }
    }
}
