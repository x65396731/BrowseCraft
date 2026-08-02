import Foundation
import UIKit

// 中文注释：平台设备信息属于 Infrastructure；仅为 BrowseCraft Portal API 生成业务请求头。
struct PortalRequestHeaderProvider: Sendable {
    private let activeAppUser: any ActiveAppUserProviding
    private let osInfo: String
    private let deviceInfo: String
    private let appVersion: String

    @MainActor
    init(activeAppUser: any ActiveAppUserProviding) {
        self.activeAppUser = activeAppUser
        let device: UIDevice = UIDevice.current
        self.osInfo = "\(device.systemName) \(device.systemVersion)"
        self.deviceInfo = Self.hardwareIdentifier() ?? device.model
        let info: [String: Any] = Bundle.main.infoDictionary ?? [:]
        let version: String = info["CFBundleShortVersionString"] as? String ?? "0"
        let build: String = info["CFBundleVersion"] as? String ?? "0"
        self.appVersion = "\(version)(\(build))"
    }

    func headers() -> [String: String] {
        return [
            "userId": self.activeAppUser.currentUserID.uuidString,
            "osInfo": self.osInfo,
            "deviceInfo": self.deviceInfo,
            "aplVersion": self.appVersion,
            "X-Request-Id": UUID().uuidString
        ]
    }

    private static func hardwareIdentifier() -> String? {
        var systemInfo: utsname = utsname()
        uname(&systemInfo)

        let mirror: Mirror = Mirror(reflecting: systemInfo.machine)
        let identifier: String = mirror.children.reduce(into: "") { result, element in
            guard let value: Int8 = element.value as? Int8, value != 0 else {
                return
            }
            result.append(String(UnicodeScalar(UInt8(value))))
        }

        return identifier.isEmpty ? nil : identifier
    }
}
