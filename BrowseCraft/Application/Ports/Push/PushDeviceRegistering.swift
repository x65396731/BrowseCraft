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
/// 调用方负责只在持有有效 access token 时调用。
protocol PushDeviceRegistering: Sendable {
    func register(
        deviceToken: String,
        environment: PushEnvironment,
        accessToken: String
    ) async throws

    func unregister(
        deviceToken: String,
        environment: PushEnvironment,
        accessToken: String
    ) async throws
}
