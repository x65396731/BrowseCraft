import Foundation

/// 中文注释：业务模块通过此边界读取当前 AppUser，不能从 CloudAccountScope 推导业务用户。
protocol ActiveAppUserProviding: Sendable {
    var currentUserID: UUID { get }
}
