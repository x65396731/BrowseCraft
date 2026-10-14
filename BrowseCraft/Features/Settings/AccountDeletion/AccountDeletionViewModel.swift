import Foundation
import Observation

// 中文注释：删除账号页（docs/design/Account-Deletion-Design.md 第三、四、八节）的状态：说明 → 确认框 → 进度遮罩 → 完成页。
// 流程本身在 `AccountDeletionCoordinator`；这里只管界面状态与文案选择。

@MainActor
@Observable
final class AccountDeletionViewModel {
    enum Phase: Equatable {
        case explaining
        case deleting
        case completed(AccountDeletionOutcome)
    }

    struct FailureAlert: Equatable {
        let title: String
        let message: String
    }

    private(set) var phase: Phase = .explaining
    var isConfirming: Bool = false
    var failureAlert: FailureAlert?

    /// 中文注释：说明页显示服务端余额；nil 时只说「coin 余额」不写数字。
    let coinBalance: @MainActor () -> Int?
    private let deleteAction: @MainActor () async throws -> AccountDeletionOutcome

    init(
        coinBalance: @escaping @MainActor () -> Int?,
        deleteAction: @escaping @MainActor () async throws -> AccountDeletionOutcome
    ) {
        self.coinBalance = coinBalance
        self.deleteAction = deleteAction
    }

    var isDeleting: Bool {
        return self.phase == .deleting
    }

    func requestConfirmation() {
        guard self.phase == .explaining else {
            return
        }
        self.isConfirming = true
    }

    func confirmDeletion() async {
        guard self.phase == .explaining else {
            return
        }
        self.phase = .deleting
        do {
            let outcome: AccountDeletionOutcome = try await self.deleteAction()
            self.phase = .completed(outcome)
        } catch let error as AccountDeletionError {
            self.phase = .explaining
            self.failureAlert = Self.alert(for: error)
        } catch {
            self.phase = .explaining
            self.failureAlert = Self.alert(for: .failed)
        }
    }

    /// 中文注释：完成页的附加说明，按需逐条显示（第八节表格的后三行）。
    static func completionNotes(for outcome: AccountDeletionOutcome) -> [String] {
        var notes: [String] = []
        if outcome.appleRevocationFailed {
            notes.append(NSLocalizedString("account_deletion_done_revoke_failed", comment: "Apple 撤销失败时的手动停用路径"))
        }
        switch outcome.localCleanup {
        case .done:
            break
        case .pending:
            notes.append(NSLocalizedString("account_deletion_done_local_pending", comment: "本机数据下次打开时清除"))
        case .reinstallRequired:
            notes.append(NSLocalizedString("account_deletion_done_local_reinstall", comment: "请删除并重新安装"))
        }
        if outcome.cloudCleanup == .pending {
            notes.append(NSLocalizedString("account_deletion_done_cloud_pending", comment: "iCloud 数据连上后清除与手动路径"))
        }
        return notes
    }

    /// 中文注释：除「结果未知」外都是「账号未删除」——标题就写这句（设计第八节的原则）。
    static func alert(for error: AccountDeletionError) -> FailureAlert? {
        let notDeleted: String = NSLocalizedString("account_deletion_failed_title", comment: "账号未删除")
        let message: String
        switch error {
        case .reauthenticationCancelled, .operationInFlight:
            return nil
        case .outcomeUnknown:
            return FailureAlert(
                title: NSLocalizedString("account_deletion_unknown_title", comment: "无法确认是否已删除"),
                message: NSLocalizedString("account_deletion_unknown_message", comment: "网络恢复后自动确认")
            )
        case .reauthenticationFailed:
            message = NSLocalizedString("account_deletion_error_reauth", comment: "无法完成 Apple 验证")
        case .sessionExpired:
            message = NSLocalizedString("account_deletion_error_session", comment: "登录已失效")
        case .verificationExpired:
            message = NSLocalizedString("account_deletion_error_verification", comment: "验证已过期")
        case .appleAccountMismatch:
            message = NSLocalizedString("account_deletion_error_mismatch", comment: "Apple ID 不一致")
        case .appleUnavailable:
            message = NSLocalizedString("account_deletion_error_apple_unavailable", comment: "Apple 服务不可用")
        case .notConfigured:
            message = NSLocalizedString("account_deletion_error_not_configured", comment: "服务暂时无法删除账号")
        case .persistenceFailed:
            message = NSLocalizedString("account_deletion_error_persistence", comment: "删除未完成，账号未受影响")
        case .rateLimited:
            message = NSLocalizedString("account_deletion_error_rate_limited", comment: "操作太频繁")
        case .network:
            message = NSLocalizedString("account_deletion_error_network", comment: "网络连接失败")
        case .failed:
            message = NSLocalizedString("account_deletion_error_generic", comment: "删除未完成")
        }
        return FailureAlert(title: notDeleted, message: message)
    }
}
