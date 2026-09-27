import SwiftUI

// 中文注释：coin 流水页（设计书 30.8）：设置页余额行点进来；每行原因、增减、记账后余额与时间。服务端为准，不做本地推算。
struct CoinLedgerView: View {
    @State private var viewModel: CoinLedgerViewModel

    init(viewModel: CoinLedgerViewModel) {
        self._viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch self.viewModel.state {
            case .idle, .loading:
                ProgressView()
            case .failed:
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: NSLocalizedString("coin_ledger_load_failed_title", comment: "流水加载失败"),
                    message: NSLocalizedString("coin_ledger_load_failed_message", comment: "流水加载失败说明")
                )
            case .loaded where self.viewModel.entries.isEmpty:
                EmptyStateView(
                    systemImage: "list.bullet.rectangle",
                    title: NSLocalizedString("coin_ledger_empty_title", comment: "还没有流水"),
                    message: NSLocalizedString("coin_ledger_empty_message", comment: "流水空态说明")
                )
            case .loaded:
                List {
                    ForEach(self.viewModel.entries) { entry in
                        CoinLedgerRow(entry: entry)
                            .task {
                                await self.viewModel.loadMoreIfNeeded(current: entry)
                            }
                    }
                    if self.viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await self.viewModel.load()
                }
            }
        }
        .navigationTitle(NSLocalizedString("coin_ledger_title", comment: "coin 流水"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await self.viewModel.load()
        }
    }
}

private struct CoinLedgerRow: View {
    let entry: CoinLedgerEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title(for: self.entry.reason))
                Text(Self.dateFormatter.string(from: self.entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: self.entry.delta > 0 ? "+\(self.entry.delta)" : String(self.entry.delta))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(self.entry.delta > 0 ? Color.green : Color.primary)
                Text(String(format: NSLocalizedString("coin_ledger_balance_after", comment: "记账后余额"), self.entry.balanceAfter))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 中文注释：原因三语；未知原因显示服务端原文，不猜。
    static func title(for reason: CoinLedgerReason) -> String {
        switch reason {
        case .signupGrant:
            return NSLocalizedString("coin_ledger_reason_signup_grant", comment: "新账户赠送")
        case .adReward:
            return NSLocalizedString("coin_ledger_reason_ad_reward", comment: "广告奖励")
        case .generationNormal:
            return NSLocalizedString("coin_ledger_reason_generation_normal", comment: "普通生成")
        case .generationHard:
            return NSLocalizedString("coin_ledger_reason_generation_hard", comment: "困难模式生成")
        case .zeroCostRefund:
            return NSLocalizedString("coin_ledger_reason_zero_cost_refund", comment: "零成本失败退回")
        case .manualAdjustment:
            return NSLocalizedString("coin_ledger_reason_manual_adjustment", comment: "客服调整")
        case .unknown(let rawValue):
            return rawValue
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
