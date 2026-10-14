import Foundation

/// 中文注释：TN3194 的客户端部分（docs/design/Account-Deletion-Design.md 第十节）：用户在系统设置里停用「通过 Apple 登录」后，
/// App 回到未登录状态。只清会话，不删任何本地数据——与退出登录同一条路径。
///
/// 中文注释：只认「见过正常之后的撤销」：这次授权之后系统至少回过一次 authorized，再查到 revoked / notFound 才退出。
/// 模拟器实测（2026-10-15）：删号撤销授权后用同一 Apple ID 重新登录，授权后 1 秒到 775 秒 getCredentialState 一直回 revoked，
/// 按状态直接退出会把刚登录的新账号反复退出去；10 分钟宽限也挡不住。代价是状态一直卡在 revoked 的用户真被撤销时不会自动退出，
/// 服务端会话照旧受控。
@MainActor
final class AppleCredentialRevocationCoordinator {
    private let checker: any AppleCredentialStateChecking
    private let userIdentifierStore: any AppleUserIdentifierStoring
    private let isSignedIn: @MainActor () async -> Bool
    private let signOut: @MainActor () async -> Void
    private let now: () -> Date
    private var notificationTask: Task<Void, Never>?
    private var isChecking: Bool = false
    /// 中文注释：自动退出后通知界面刷新登录状态（设置页只在出现时自己刷新）；组合根在 Features 装好后设置。
    var didSignOut: (@MainActor () async -> Void)?

    init(
        checker: any AppleCredentialStateChecking,
        userIdentifierStore: any AppleUserIdentifierStoring,
        isSignedIn: @escaping @MainActor () async -> Bool,
        signOut: @escaping @MainActor () async -> Void,
        now: @escaping () -> Date = Date.init
    ) {
        self.checker = checker
        self.userIdentifierStore = userIdentifierStore
        self.isSignedIn = isSignedIn
        self.signOut = signOut
        self.now = now
    }

    deinit {
        self.notificationTask?.cancel()
    }

    /// 中文注释：启动时调用一次：开始监听撤销通知，并立即查一次状态。
    func start() async {
        if self.notificationTask == nil {
            let notifications: AsyncStream<Void> = self.checker.revocationNotifications()
            self.notificationTask = Task { [weak self] in
                for await _ in notifications {
                    guard Task.isCancelled == false else {
                        return
                    }
                    await self?.handleRevocation(reason: "notification")
                }
            }
        }
        await self.checkCredentialState()
    }

    /// 中文注释：启动与回到前台时调用。没登录、或没存过 Apple user 标识（存量用户）就跳过。
    func checkCredentialState() async {
        guard self.isChecking == false else {
            return
        }
        self.isChecking = true
        defer {
            self.isChecking = false
        }
        guard await self.isSignedIn(),
              let userIdentifier: String = try? self.userIdentifierStore.loadUserIdentifier() else {
            return
        }
        let state: AppleCredentialState = await self.checker.credentialState(forUserIdentifier: userIdentifier)
        PortalSessionDiagnostics.notice(
            "event=apple-credential-state state=\(state) " +
                "secondsSinceAuthorization=\(self.secondsSinceAuthorization().map { String(Int($0)) } ?? "unknown")"
        )
        switch state {
        case .revoked:
            await self.handleRevocation(reason: "revoked")
        case .notFound:
            await self.handleRevocation(reason: "not-found")
        case .authorized:
            do {
                try self.userIdentifierStore.markObservedAuthorized()
            } catch {
                PortalSessionDiagnostics.error("event=apple-credential-observed-save result=failed")
            }
        case .transferred, .unknown:
            return
        }
    }

    private func handleRevocation(reason: String) async {
        guard await self.isSignedIn() else {
            return
        }
        guard (try? self.userIdentifierStore.hasObservedAuthorized()) == true else {
            PortalSessionDiagnostics.notice(
                "event=apple-credential-revoked reason=\(reason) action=ignored-not-yet-authorized " +
                    "secondsSinceAuthorization=\(self.secondsSinceAuthorization().map { String(Int($0)) } ?? "unknown")"
            )
            return
        }
        PortalSessionDiagnostics.notice(
            "event=apple-credential-revoked reason=\(reason) action=sign-out"
        )
        await self.signOut()
        await self.didSignOut?()
    }

    private func secondsSinceAuthorization() -> TimeInterval? {
        guard let authorizedAt: Date = try? self.userIdentifierStore.lastAuthorizedAt() else {
            return nil
        }
        return max(0, self.now().timeIntervalSince(authorizedAt))
    }
}
