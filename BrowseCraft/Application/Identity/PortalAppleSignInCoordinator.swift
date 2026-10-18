import BrowseCraftLog
import Foundation

enum PortalAppleSignInError: Error, Equatable, Sendable {
    case operationInFlight
    case activeUserChanged
    case accountTransitionFailed
    case sessionInstallationFailed
}

/// 中文注释：串联后端 challenge、原生 Apple 授权、Portal Token 交换与本地 AppUser 切换。
actor PortalAppleSignInCoordinator {
    private let activeAppUser: ActiveAppUserStore
    private let portalSessionCoordinator: PortalSessionCoordinator
    private let appleAuthorizer: any AppleSignInAuthorizing
    private let identityAdoptionCoordinator: AppUserIdentityAdoptionCoordinator
    private let identityOriginStore: any PortalAppUserIdentityOriginStoring
    private let appleUserIdentifierStore: (any AppleUserIdentifierStoring)?
    /// 中文注释：新注册且拿到赠送时调用一次（Campaign-And-Rate-Notices-Design.md 第五节）。由组合根接到
    /// In-App Messaging 的 `welcome_new_account` 触发；Application 层不引用 Firebase。
    private let newAccountWelcomeHandler: (@Sendable () async -> Void)?
    private var operationInFlight: Bool = false

    init(
        activeAppUser: ActiveAppUserStore,
        portalSessionCoordinator: PortalSessionCoordinator,
        appleAuthorizer: any AppleSignInAuthorizing,
        identityAdoptionCoordinator: AppUserIdentityAdoptionCoordinator,
        identityOriginStore: any PortalAppUserIdentityOriginStoring,
        appleUserIdentifierStore: (any AppleUserIdentifierStoring)? = nil,
        newAccountWelcomeHandler: (@Sendable () async -> Void)? = nil
    ) {
        self.activeAppUser = activeAppUser
        self.portalSessionCoordinator = portalSessionCoordinator
        self.appleAuthorizer = appleAuthorizer
        self.identityAdoptionCoordinator = identityAdoptionCoordinator
        self.identityOriginStore = identityOriginStore
        self.appleUserIdentifierStore = appleUserIdentifierStore
        self.newAccountWelcomeHandler = newAccountWelcomeHandler
    }

    @discardableResult
    func signIn() async throws -> UUID {
        guard self.operationInFlight == false else {
            throw PortalAppleSignInError.operationInFlight
        }
        self.operationInFlight = true
        defer {
            self.operationInFlight = false
        }

        let startingUserID: UUID = self.activeAppUser.currentUserID
        let challenge: PortalAppleAuthenticationChallenge =
            try await self.portalSessionCoordinator.issueAppleChallenge()
        let authorization: AppleSignInAuthorization = try await self.appleAuthorizer.authorize(
            nonce: challenge.nonce
        )
        let authentication: PortalAppleAuthentication =
            try await self.portalSessionCoordinator.authenticateWithApple(
                identityToken: authorization.identityToken,
                nonce: challenge.nonce
            )
        let credentials: PortalAuthenticationTokens = authentication.tokens

        guard self.activeAppUser.currentUserID == startingUserID else {
            await self.portalSessionCoordinator.discardUninstalledCredentials(
                credentials
            )
            throw PortalAppleSignInError.activeUserChanged
        }
        let startingIdentityIsPortalUser: Bool
        do {
            startingIdentityIsPortalUser = try self.identityOriginStore
                .containsPortalUserID(startingUserID)
            try self.identityOriginStore.markPortalUserID(credentials.userID)
        } catch {
            await self.portalSessionCoordinator.discardUninstalledCredentials(
                credentials
            )
            throw PortalAppleSignInError.accountTransitionFailed
        }
        if credentials.userID != startingUserID {
            let decision: CloudAccountLocalDataDecision =
                startingIdentityIsPortalUser
                    ? .useCloudDataOnly
                    : .mergeLocalData
            var transitionID: UUID?
            do {
                transitionID = try await self.portalSessionCoordinator
                    .stageAuthenticatedSessionTransition(
                        credentials,
                        from: startingUserID
                    )
                guard let transitionID else {
                    throw PortalAppleSignInError.accountTransitionFailed
                }
                _ = try await self.identityAdoptionCoordinator
                    .adoptAuthenticatedPortalUser(
                        localUserID: startingUserID,
                        portalUserID: credentials.userID,
                        decision: decision,
                        sessionTransitionID: transitionID
                    )
            } catch {
                if let transitionID {
                    await self.portalSessionCoordinator
                        .rollbackAuthenticatedSessionTransition(transitionID)
                } else {
                    await self.portalSessionCoordinator.discardUninstalledCredentials(
                        credentials
                    )
                }
                throw PortalAppleSignInError.accountTransitionFailed
            }
        } else {
            do {
                try await self.portalSessionCoordinator.installAuthenticatedSession(
                    credentials
                )
            } catch {
                await self.portalSessionCoordinator.discardUninstalledCredentials(
                    credentials
                )
                throw PortalAppleSignInError.sessionInstallationFailed
            }
        }
        // 中文注释：登录成功后才记 Apple user 标识，供启动与回到前台时查凭据状态（删除账号设计第十节）；写失败只是少一次检查。
        do {
            try self.appleUserIdentifierStore?.saveUserIdentifier(authorization.userIdentifier)
        } catch {
            AppLog.error(.identity, "apple-user-identifier-save-failed")
        }
        // 中文注释：走到这里 Apple 登录面板早已收起、会话也已装好；赠送在建号事务里已入账，
        // 欢迎页只是告知（`BCA-SYNC-012`）。
        if authentication.welcomesNewAccount, let handler = self.newAccountWelcomeHandler {
            AppLog.notice(.identity, "new-account-welcome-triggered")
            await handler()
        }
        return credentials.userID
    }

}
