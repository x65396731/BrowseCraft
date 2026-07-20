import Foundation
import UIKit

// 中文注释：仅为 BrowseCraft Portal API 生成业务请求头，禁止复用到第三方 source 请求。
struct PortalRequestHeaderProvider {
    private let appUserRepository: AppUserRepository

    init(appUserRepository: AppUserRepository) {
        self.appUserRepository = appUserRepository
    }

    func headers() -> [String: String] {
        return [
            "userId": self.userID(),
            "osInfo": self.osInfo,
            "deviceInfo": self.deviceInfo,
            "aplVersion": self.appVersion,
            "X-Request-Id": UUID().uuidString
        ]
    }

    private func userID() -> String {
        do {
            return try self.appUserRepository.fetchUser(id: AppUser.localDefaultID)?.id
                ?? AppUser.localDefaultID
        } catch {
            return AppUser.localDefaultID
        }
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
