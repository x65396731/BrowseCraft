import Foundation

/// 中文注释：账户状态边界不暴露 CKAccountStatus 或 CloudKit user record ID。
protocol CloudAccountStateProviding: Sendable {
    func currentState() async -> CloudAccountState
    func stateUpdates() async -> AsyncStream<CloudAccountState>
    func startMonitoring() async
    func stopMonitoring() async
    func refresh() async
}
