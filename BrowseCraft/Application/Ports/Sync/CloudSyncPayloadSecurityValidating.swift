import Foundation

protocol CloudSyncPayloadSecurityValidating: Sendable {
    func validate(_ payload: SourceCloudPayload) throws
    func validate(_ payload: FavoriteItemCloudPayload) throws
}

enum CloudSyncPayloadSecurityIssue: String, Hashable, Sendable {
    case invalidJSON
    case payloadTooLarge
    case localAccountIdentity
    case urlUserInfo
}

struct CloudSyncPayloadSecurityError: Error, Hashable, Sendable, CustomStringConvertible {
    var path: String
    var issue: CloudSyncPayloadSecurityIssue
    var fieldName: String?

    var description: String {
        var components: [String] = [
            "Cloud payload rejected",
            "issue=\(self.issue.rawValue)",
            "path=\(self.path)"
        ]
        if let fieldName: String = self.fieldName {
            components.append("field=\(fieldName)")
        }
        return components.joined(separator: " ")
    }
}
