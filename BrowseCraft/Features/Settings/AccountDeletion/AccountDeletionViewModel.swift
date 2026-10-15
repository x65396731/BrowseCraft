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

    /// 中文注释：完成页结果清单的一项。done 打绿勾；needsAttention 要用户自己动手；waiting 由 App 稍后自动续做。
    struct CompletionItem: Equatable {
        enum Status: Equatable {
            case done
            case needsAttention
            case waiting
        }

        let title: String
        let status: Status
        let statusText: String
        let detail: String?
    }

    /// 中文注释：完成页的结果清单（第八节表格的后三行逐项落到这里）：服务端删除总是完成；
    /// Apple 授权、本机数据、iCloud 数据按 `AccountDeletionOutcome` 显示完成或附上说明。
    static func completionItems(for outcome: AccountDeletionOutcome) -> [CompletionItem] {
        let cleared: String = NSLocalizedString("account_deletion_done_status_cleared", comment: "已清除")
        let actionNeeded: String = NSLocalizedString("account_deletion_done_status_action_needed", comment: "需要你处理")
        var items: [CompletionItem] = [
            CompletionItem(
                title: NSLocalizedString("account_deletion_done_item_account", comment: "账号与 coin"),
                status: .done,
                statusText: NSLocalizedString("account_deletion_done_status_deleted", comment: "已删除"),
                detail: nil
            )
        ]

        let appleTitle: String = NSLocalizedString("account_deletion_row_apple_title", comment: "通过 Apple 登录的授权")
        if outcome.appleRevocationFailed {
            items.append(CompletionItem(
                title: appleTitle,
                status: .needsAttention,
                statusText: actionNeeded,
                detail: NSLocalizedString("account_deletion_done_revoke_failed", comment: "Apple 撤销失败时的手动停用路径")
            ))
        } else {
            items.append(CompletionItem(
                title: appleTitle,
                status: .done,
                statusText: NSLocalizedString("account_deletion_done_status_revoked", comment: "已撤销"),
                detail: nil
            ))
        }

        let localTitle: String = NSLocalizedString("account_deletion_done_item_local", comment: "本机数据")
        switch outcome.localCleanup {
        case .done:
            items.append(CompletionItem(title: localTitle, status: .done, statusText: cleared, detail: nil))
        case .pending:
            items.append(CompletionItem(
                title: localTitle,
                status: .waiting,
                statusText: NSLocalizedString("account_deletion_done_status_next_launch", comment: "下次打开时清除"),
                detail: NSLocalizedString("account_deletion_done_local_pending", comment: "本机数据下次打开时清除")
            ))
        case .reinstallRequired:
            items.append(CompletionItem(
                title: localTitle,
                status: .needsAttention,
                statusText: actionNeeded,
                detail: NSLocalizedString("account_deletion_done_local_reinstall", comment: "请删除并重新安装")
            ))
        }

        let cloudTitle: String = NSLocalizedString("account_deletion_done_item_cloud", comment: "iCloud 数据")
        switch outcome.cloudCleanup {
        case .done:
            items.append(CompletionItem(title: cloudTitle, status: .done, statusText: cleared, detail: nil))
        case .pending:
            items.append(CompletionItem(
                title: cloudTitle,
                status: .waiting,
                statusText: NSLocalizedString("account_deletion_done_status_waiting_icloud", comment: "等待 iCloud"),
                detail: NSLocalizedString("account_deletion_done_cloud_pending", comment: "iCloud 数据连上后清除与手动路径")
            ))
        }
        return items
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
