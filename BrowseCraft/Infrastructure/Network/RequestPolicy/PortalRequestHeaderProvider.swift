import Foundation
import UIKit

// 中文注释：平台设备信息属于 Infrastructure；仅为 BrowseCraft Portal API 生成业务请求头。
struct PortalRequestHeaderProvider {
    private let activeAppUser: any ActiveAppUserProviding

    init(activeAppUser: any ActiveAppUserProviding) {
        self.activeAppUser = activeAppUser
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

    private var osInfo: String {
        let device: UIDevice = UIDevice.current
        return "\(device.systemName) \(device.systemVersion)"
    }

    private var deviceInfo: String {
        return Self.hardwareIdentifier() ?? UIDevice.current.model
    }

    private var appVersion: String {
        let info: [String: Any] = Bundle.main.infoDictionary ?? [:]
        let version: String = info["CFBundleShortVersionString"] as? String ?? "0"
        let build: String = info["CFBundleVersion"] as? String ?? "0"
        return "\(version)(\(build))"
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
