import Foundation

enum PortalAPIConfiguration {
    private static let managedDomain: String = "anyportal.online"

    /// 中文注释：隐私权政策页（PortalCore `GET /privacy`，审核指南 5.1.1(i)）；App Store Connect 填的是同一个网址。
    static let privacyPolicyURL: URL? = URL(string: "https://\(managedDomain)/privacy")

    static func isManagedAPIURL(_ url: URL) -> Bool {
        guard let host: String = url.host?.lowercased() else {
            return false
        }

        return host == self.managedDomain || host.hasSuffix(".\(self.managedDomain)")
    }
}
