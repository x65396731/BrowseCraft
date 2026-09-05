import Foundation

/// 中文注释：APNs device token → PortalCore `/v1/push/devices` 的注册协调器（`BC-PREFLIGHT-057`）。
///
/// 只在「已拿到 token 且 Portal 会话有效」时注册；token 或登录用户任一变化都重新注册，
/// 服务端按 token upsert 并改写归属用户。注册失败不重试、不冒泡——推送是附加能力，
/// 下一次 app 激活或登录时 `synchronizeRegistration()` 会再试。
actor PushDeviceRegistrationCoordinator {
    private let environment: PushEnvironment
    private let registrar: any PushDeviceRegistering
    private let sessionCoordinator: PortalSessionCoordinator

    private var deviceToken: String?
    private var registration: Registration?
    /// 中文注释：actor 在 await 期间可重入——启动对齐与 token 回调同时到达时，第一次还在等网络，
    /// 第二次看到 `registration == nil` 会再发一遍。记下在途目标，重复目标直接跳过。
    private var inFlightRegistration: Registration?

    private struct Registration: Equatable, Sendable {
        let deviceToken: String
        let userID: UUID
    }

    init(
        environment: PushEnvironment,
        registrar: any PushDeviceRegistering,
        sessionCoordinator: PortalSessionCoordinator
    ) {
        self.environment = environment
        self.registrar = registrar
        self.sessionCoordinator = sessionCoordinator
    }

    /// APNs 交回新 token 时调用。token 可能在重装、恢复备份后变化，相同值不重复注册。
    func updateDeviceToken(_ deviceToken: String) async {
        guard deviceToken != self.deviceToken else {
            return
        }
        self.deviceToken = deviceToken
        await self.synchronizeRegistration()
    }

    /// 让服务端记录与本地 (token, 用户) 对齐；无 token 或未登录时静默返回。
    func synchronizeRegistration() async {
        guard let deviceToken: String = self.deviceToken else {
            return
        }
        guard let userID: UUID = await self.sessionCoordinator.authenticatedUserID(),
              let accessToken: String = await self.sessionCoordinator.validAccessToken() else {
            return
        }
        let target: Registration = Registration(deviceToken: deviceToken, userID: userID)
        guard target != self.registration, target != self.inFlightRegistration else {
            return
        }
        self.inFlightRegistration = target
        defer {
            self.inFlightRegistration = nil
        }
        do {
            try await self.registrar.register(
                deviceToken: deviceToken,
                environment: self.environment,
                accessToken: accessToken
            )
            self.registration = target
            AppLog.notice(
                .push,
                event: "device-registered",
                metadata: ["environment": self.environment.rawValue]
            )
        } catch is CancellationError {
            return
        } catch {
            // 中文注释：只记分类，不记 token（AGENTS.md §2.6）。
            AppLog.error(
                .push,
                event: "device-registration-failed",
                metadata: [
                    "environment": self.environment.rawValue,
                    "error": Self.describe(error)
                ]
            )
        }
    }

    /// 登出前调用：趁 access token 还有效注销当前设备。失败只记日志——服务端在
    /// 下一次投递拿到 410 会自行清理；无论成败都清空本地记录，换账户登录时重新注册。
    func unregisterCurrentDevice() async {
        defer {
            self.registration = nil
        }
        guard let deviceToken: String = self.deviceToken,
              let accessToken: String = await self.sessionCoordinator.validAccessToken() else {
            return
        }
        do {
            try await self.registrar.unregister(
                deviceToken: deviceToken,
                environment: self.environment,
                accessToken: accessToken
            )
            AppLog.notice(.push, event: "device-unregistered")
        } catch is CancellationError {
            return
        } catch {
            AppLog.error(
                .push,
                event: "device-unregistration-failed",
                metadata: ["error": Self.describe(error)]
            )
        }
    }

    private static func describe(_ error: any Error) -> String {
        guard let registrationError: PushDeviceRegistrationError =
            error as? PushDeviceRegistrationError else {
            return AppLog.safeErrorCode(error)
        }
        switch registrationError {
        case .authRequired:
            return "auth-required"
        case .rejected(let code):
            return "rejected:\(code)"
        case .transport:
            return "transport"
        }
    }
}
