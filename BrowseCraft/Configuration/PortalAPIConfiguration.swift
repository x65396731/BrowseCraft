import Foundation

enum PortalAPIConfiguration {
    private static let managedDomain: String = "anyportal.online"

    static func isManagedAPIURL(_ url: URL) -> Bool {
        guard let host: String = url.host?.lowercased() else {
            return false
        }

        return host == self.managedDomain || host.hasSuffix(".\(self.managedDomain)")
    }
}
