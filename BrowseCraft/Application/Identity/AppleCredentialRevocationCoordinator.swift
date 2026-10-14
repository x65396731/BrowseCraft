import Foundation

/// 中文注释：TN3194 的客户端部分（docs/design/Account-Deletion-Design.md 第十节）：用户在系统设置里停用「通过 Apple 登录」后，
/// App 回到未登录状态。只清会话，不删任何本地数据——与退出登录同一条路径。
@MainActor
final class AppleCredentialRevocationCoordinator {
    private let checker: any AppleCredentialStateChecking
    private let userIdentifierStore: any AppleUserIdentifierStoring
    private let isSignedIn: @MainActor () async -> Bool
    private let signOut: @MainActor () async -> Void
    private var notificationTask: Task<Void, Never>?
    private var isChecking: Bool = false

    init(
        checker: any AppleCredentialStateChecking,
        userIdentifierStore: any AppleUserIdentifierStoring,
        isSignedIn: @escaping @MainActor () async -> Bool,
        signOut: @escaping @MainActor () async -> Void
    ) {
        self.checker = checker
        self.userIdentifierStore = userIdentifierStore
        self.isSignedIn = isSignedIn
        self.signOut = signOut
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
        switch await self.checker.credentialState(forUserIdentifier: userIdentifier) {
        case .revoked:
            await self.handleRevocation(reason: "revoked")
        case .notFound:
            await self.handleRevocation(reason: "not-found")
        case .authorized, .transferred, .unknown:
            return
        }
    }

    private func handleRevocation(reason: String) async {
        guard await self.isSignedIn() else {
            return
        }
        PortalSessionDiagnostics.notice(
            "event=apple-credential-revoked reason=\(reason) action=sign-out"
        )
        await self.signOut()
    }
}
