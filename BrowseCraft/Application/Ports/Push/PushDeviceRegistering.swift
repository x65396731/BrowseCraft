import Foundation

/// APNs 设备 token 所属环境（`BC-PREFLIGHT-057`）。
///
/// 中文注释：与 `project.yml` 的 `APS_ENVIRONMENT` 一一对应——Debug 是 `development`
/// 即 sandbox，Release / TestFlight 是 `production`。由组合根按构建配置决定，
/// 不在运行期探测。
enum PushEnvironment: String, Equatable, Sendable {
    case sandbox
    case production
}

/// 设备注册客户端的稳定错误分类；由 Infrastructure 适配器从 transport 错误映射而来。
enum PushDeviceRegistrationError: Error, Equatable, Sendable {
    case authRequired
    case rejected(code: String)
    case transport
}

/// 向 PortalCore 注册 / 注销推送设备的 Application 端口。
///
/// 中文注释：`deviceToken` 是 APNs 交回的原始 token 的小写十六进制串，实现不得改写；
/// 调用方负责只在持有有效 access token 时调用。`marketingOptIn` 是设置页「活动推送」开关，
/// `language` 是 App 当前界面语言（en / zh-Hans / zh-Hant），两者只随登记发送
/// （Campaign-And-Rate-Notices-Design.md 第四节，`BCA-UI-005`）。
protocol PushDeviceRegistering: Sendable {
    func register(
        deviceToken: String,
        environment: PushEnvironment,
        marketingOptIn: Bool,
        language: String,
        accessToken: String
    ) async throws

    func unregister(
        deviceToken: String,
        environment: PushEnvironment,
        accessToken: String
    ) async throws
}

/// 「活动推送」开关的本机存储（Campaign-And-Rate-Notices-Design.md 第四节）。
///
/// 中文注释：值存在本机、默认关；登出时设备照旧注销、这里的值不动，重新登录后按它重新同步。
protocol CampaignPushPreferenceStoring: Sendable {
    func isCampaignPushEnabled() -> Bool
    func setCampaignPushEnabled(_ enabled: Bool)
}
