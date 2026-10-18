import BrowseCraftLog
import Foundation

/// 中文注释：APNs device token → PortalCore `/v1/push/devices` 的注册协调器（`BC-PREFLIGHT-057`）。
///
/// 只在「已拿到 token 且 Portal 会话有效」时注册；token、登录用户、「活动推送」开关或界面语言任一变化都重新注册，
/// 服务端按 token upsert 并改写归属用户与同意标记。注册失败不重试、不冒泡——推送是附加能力，
/// 下一次 app 激活或登录时 `synchronizeRegistration()` 会再试。
///
/// 「活动推送」开关（Campaign-And-Rate-Notices-Design.md 第四节，`BCA-UI-005`）只决定服务端发活动推送时是否包含这台设备，
/// 不影响生成结果推送；值存在本机，登出时设备照旧注销，重新登录后按本机值重新同步。
actor PushDeviceRegistrationCoordinator {
    private let environment: PushEnvironment
    private let registrar: any PushDeviceRegistering
    private let sessionCoordinator: PortalSessionCoordinator
    /// 中文注释：nil 时（测试替身）按开关关处理。
    private let campaignPushPreferenceStore: (any CampaignPushPreferenceStoring)?
    /// 中文注释：App 当前界面语言（en / zh-Hans / zh-Hant），活动推送按它取三语文案之一；由组合根从主 bundle 读。
    private let languageProvider: @Sendable () -> String

    private var deviceToken: String?
    private var registration: Registration?
    /// 中文注释：actor 在 await 期间可重入——启动对齐与 token 回调同时到达时，第一次还在等网络，
    /// 第二次看到 `registration == nil` 会再发一遍。记下在途目标，重复目标直接跳过。
    private var inFlightRegistration: Registration?

    private struct Registration: Equatable, Sendable {
        let deviceToken: String
        let userID: UUID
        let marketingOptIn: Bool
        let language: String
    }

    init(
        environment: PushEnvironment,
        registrar: any PushDeviceRegistering,
        sessionCoordinator: PortalSessionCoordinator,
        campaignPushPreferenceStore: (any CampaignPushPreferenceStoring)? = nil,
        languageProvider: @escaping @Sendable () -> String = { "en" }
    ) {
        self.environment = environment
        self.registrar = registrar
        self.sessionCoordinator = sessionCoordinator
        self.campaignPushPreferenceStore = campaignPushPreferenceStore
        self.languageProvider = languageProvider
    }

    /// 设置页「活动推送」开关的当前值（本机）。
    func isCampaignPushEnabled() -> Bool {
        return self.campaignPushPreferenceStore?.isCampaignPushEnabled() ?? false
    }

    /// 用户拨动「活动推送」开关：先存本机，再随设备登记把同意标记同步到 PortalCore。
    /// 未登录或还没拿到 token 时只存本机，之后登录或拿到 token 时自然带上。
    func setCampaignPushEnabled(_ enabled: Bool) async {
        self.campaignPushPreferenceStore?.setCampaignPushEnabled(enabled)
        AppLog.notice(.push, "campaign-push-preference-changed", ["enabled": .bool(enabled)])
        await self.synchronizeRegistration()
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
        let target: Registration = Registration(
            deviceToken: deviceToken,
            userID: userID,
            marketingOptIn: self.isCampaignPushEnabled(),
            language: self.languageProvider()
        )
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
                marketingOptIn: target.marketingOptIn,
                language: target.language,
                accessToken: accessToken
            )
            self.registration = target
            AppLog.notice(.push, "device-registered", [
                "environment": .enumValue(self.environment),
                "marketingOptIn": .bool(target.marketingOptIn),
                "language": .code(target.language)
            ])
        } catch is CancellationError {
            return
        } catch {
            // 中文注释：只记分类，不记 token（AGENTS.md §2.6）。
            AppLog.error(.push, "device-registration-failed", ["environment": .enumValue(self.environment), "error": .error(error)])
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
            AppLog.notice(.push, "device-unregistered")
        } catch is CancellationError {
            return
        } catch {
            AppLog.error(.push, "device-unregistration-failed", ["error": .error(error)])
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
