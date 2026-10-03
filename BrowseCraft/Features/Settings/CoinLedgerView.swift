import SwiftUI

// 中文注释：coin 记录页（`docs/design/Coin-Ledger-Page-Redesign-Design.md`）：设置页账号卡「coin 记录 ›」推进来；
// 余额卡 + 按天分组的记录。服务端为准，不做本地推算；本页只改展示，数据仍由 `CoinLedgerViewModel` 翻页取。
struct CoinLedgerView: View {
    @State private var viewModel: CoinLedgerViewModel
    /// 余额与价格与设置页同一个来源。
    let wallet: CoinWalletStore

    init(viewModel: CoinLedgerViewModel, wallet: CoinWalletStore) {
        self._viewModel = State(wrappedValue: viewModel)
        self.wallet = wallet
    }

    var body: some View {
        // 中文注释：所有状态都放在同一个可下拉的滚动内容里——原来只有加载成功的列表能下拉，
        // 失败页写着「下拉重试」却拉不动。
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CoinLedgerBalanceCard(balanceText: self.balanceText, pricing: self.wallet.pricing)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                self.content
            }
            .padding(.bottom, 24)
        }
        .background(CatalogPalette.pageBackground)
        .navigationTitle(NSLocalizedString("coin_ledger_title", comment: "coin 记录"))
        .navigationBarTitleDisplayMode(.inline)
        // 中文注释：二级页隐藏底栏，左上返回是唯一出口（用户裁定）；返回设置页时底栏自动回来。
        .toolbar(.hidden, for: .tabBar)
        .refreshable {
            await self.viewModel.load()
            await self.wallet.refresh()
        }
        .task {
            await self.viewModel.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch self.viewModel.state {
        case .idle, .loading:
            CoinLedgerSkeleton()
        case .failed:
            CoinLedgerStateView(
                systemImage: "exclamationmark.triangle",
                title: NSLocalizedString("coin_ledger_load_failed_title", comment: "流水加载失败"),
                message: NSLocalizedString("coin_ledger_load_failed_message", comment: "流水加载失败说明"),
                showsPullHint: true
            )
        case .loaded where self.viewModel.entries.isEmpty:
            CoinLedgerStateView(
                systemImage: "list.bullet.rectangle",
                title: NSLocalizedString("coin_ledger_empty_title", comment: "还没有流水"),
                message: NSLocalizedString("coin_ledger_empty_message", comment: "流水空态说明"),
                showsPullHint: false
            )
        case .loaded:
            ForEach(self.dayGroups) { group in
                Text(CatalogDayTitle.text(for: group.day))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 64)
                        }
                        CoinLedgerRow(entry: entry)
                            .task {
                                await self.viewModel.loadMoreIfNeeded(current: entry)
                            }
                    }
                }
                .background(CatalogPalette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 20)
            }

            self.footer
        }
    }

    /// 列表末尾：翻页中转圈；已到底写一句；中间态（还有更多但没在取）什么都不放。
    @ViewBuilder
    private var footer: some View {
        if self.viewModel.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        } else if self.viewModel.hasMore == false {
            Text(NSLocalizedString("coin_ledger_end", comment: "没有更早的记录了"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
    }

    /// 余额取钱包（与设置页同一个数）；还没拿到时用第一条记录的记账后余额，都没有写「—」。
    private var balanceText: String {
        if let balance: Int = self.wallet.balance {
            return String(balance)
        }
        if let latest: CoinLedgerEntry = self.viewModel.entries.first {
            return String(latest.balanceAfter)
        }
        return "—"
    }

    /// 按记账日期分组，组内保持服务端的时间倒序。
    private var dayGroups: [CoinLedgerDayGroup] {
        let now: Date = Date()
        let calendar: Calendar = .current
        var groups: [CoinLedgerDayGroup] = []
        for entry in self.viewModel.entries {
            let day: CatalogPersonalTimeline.Day = CatalogPersonalTimeline.day(for: entry.createdAt, now: now, calendar: calendar)
            if let last: CoinLedgerDayGroup = groups.last, last.day == day {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append(CoinLedgerDayGroup(day: day, entries: [entry]))
            }
        }
        return groups
    }
}

private struct CoinLedgerDayGroup: Identifiable {
    let day: CatalogPersonalTimeline.Day
    var entries: [CoinLedgerEntry]

    var id: CatalogPersonalTimeline.Day {
        return self.day
    }
}

/// 余额卡：当前余额 + 服务端下发的价格说明（用户裁定保留，看到一笔 −300 能对上困难模式）。不放按钮。
private struct CoinLedgerBalanceCard: View {
    let balanceText: String
    let pricing: CoinPricing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("coin_ledger_current_balance", comment: "当前余额"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: self.balanceText)
                        .font(.title.weight(.heavy))
                        .monospacedDigit()
                    Text(verbatim: "coin")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Divider()

            Text(String(
                format: NSLocalizedString("coin_ledger_pricing", comment: "价格说明"),
                self.pricing.normal,
                self.pricing.hard,
                self.pricing.adReward
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 一笔变动：原因图标 + 原因与时刻 + 增减与记账后余额。行不可点。
private struct CoinLedgerRow: View {
    let entry: CoinLedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbolName(for: self.entry.reason))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(self.isGain ? CatalogPalette.settingsIcon : Color.secondary)
                .frame(width: 36, height: 36)
                .background(self.isGain ? CatalogPalette.settingsIconFill : CatalogPalette.fillBackground, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: self.entry.reason))
                    .font(.body)
                    .lineLimit(1)
                Text(Self.timeFormatter.string(from: self.entry.createdAt))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: self.deltaText)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(self.isGain ? CatalogPalette.gain : Color.primary)
                Text(String(format: NSLocalizedString("coin_ledger_balance_after", comment: "记账后余额"), self.entry.balanceAfter))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// 进与出按增减正负分：客服调整与未知原因也能正确归类。
    private var isGain: Bool {
        return self.entry.delta > 0
    }

    /// 消耗用印刷体减号「−」，与「+」等宽对齐。
    private var deltaText: String {
        return self.entry.delta > 0 ? "+\(self.entry.delta)" : "\u{2212}\(abs(self.entry.delta))"
    }

    static func symbolName(for reason: CoinLedgerReason) -> String {
        switch reason {
        case .signupGrant:
            return "gift.fill"
        case .adReward:
            return "play.fill"
        case .zeroCostRefund:
            return "arrow.uturn.backward"
        case .manualAdjustment:
            return "person.fill"
        case .generationNormal, .generationHard:
            return "sparkles"
        case .unknown:
            return "questionmark"
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

    /// 日期已在组头，行内只写时刻。
    private static let timeFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

/// 首次加载：与正式行同形的骨架，加载完成后不跳动。
private struct CoinLedgerSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(CatalogPalette.fillBackground)
                .frame(width: 48, height: 12)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 64)
                    }
                    HStack(spacing: 12) {
                        Circle()
                            .fill(CatalogPalette.fillBackground)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(CatalogPalette.fillBackground)
                                .frame(width: 140, height: 12)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(CatalogPalette.fillBackground)
                                .frame(width: 56, height: 10)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 8) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(CatalogPalette.fillBackground)
                                .frame(width: 44, height: 12)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(CatalogPalette.fillBackground)
                                .frame(width: 60, height: 10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(CatalogPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Loading", comment: ""))
    }
}

/// 失败与空：图标 + 标题 + 说明；失败时多一行「下拉可重试」，页面真的能下拉。
private struct CoinLedgerStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let showsPullHint: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: self.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(CatalogPalette.fillBackground, in: Circle())
                .accessibilityHidden(true)
            Text(self.title)
                .font(.headline)
            Text(self.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if self.showsPullHint {
                Label(NSLocalizedString("cloud_restore_pull_to_retry", comment: ""), systemImage: "arrow.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CatalogPalette.settingsIcon)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 56)
    }
}
