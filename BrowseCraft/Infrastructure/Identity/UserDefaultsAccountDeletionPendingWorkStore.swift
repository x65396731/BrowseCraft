import Foundation

/// 中文注释：删号未完成工作的标记（docs/design/Account-Deletion-Design.md 第七节）。只存被删账号的 UUID 与 iCloud 分区散列，
/// 不含凭据；读不出（被清或格式不对）时按没有待办处理。
/// 中文注释：`@unchecked` 的依据（architecture.md 第 4 节）：成员全不可变；`UserDefaults` 自身线程安全，读改写只在 MainActor 上的删号协调器里发生。
final class UserDefaultsAccountDeletionPendingWorkStore: AccountDeletionPendingWorkStoring, @unchecked Sendable {
    static let defaultsKey: String = "account-deletion.pending-work.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AccountDeletionPendingWork {
        guard let data: Data = self.defaults.data(forKey: Self.defaultsKey),
              let work: AccountDeletionPendingWork = try? JSONDecoder().decode(
                AccountDeletionPendingWork.self,
                from: data
              ) else {
            return AccountDeletionPendingWork()
        }
        return work
    }

    func save(_ work: AccountDeletionPendingWork) {
        guard work.isEmpty == false else {
            self.defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        guard let data: Data = try? JSONEncoder().encode(work) else {
            return
        }
        self.defaults.set(data, forKey: Self.defaultsKey)
    }
}
