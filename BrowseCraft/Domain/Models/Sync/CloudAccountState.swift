import Foundation

/// 中文注释：CloudAccountAvailability 隔离 CloudKit 类型，供 Application 和 Feature 层安全使用。
enum CloudAccountAvailability: String, Codable, Hashable, Sendable {
    case notChecked
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

struct CloudAccountState: Hashable, Sendable {
    var availability: CloudAccountAvailability
    var scope: CloudAccountScope

    static let initial: CloudAccountState = CloudAccountState(
        availability: .notChecked,
        scope: .localDefault
    )

    var synchronizationScope: CloudAccountScope? {
        guard self.availability == .available,
              self.scope.isCloud else {
            return nil
        }
        return self.scope
    }
}
