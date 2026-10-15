import SwiftUI

// 中文注释：删除账号页（docs/design/Account-Deletion-Design.md 第三、四、八节）：从设置页「删除账号」推进来。
// 顶部图标与大标题 → 会删除 / 会保留 / 删除前请留意三张卡 → 接下来三步 → 「继续删除」→ 系统居中确认框
// （不用 confirmationDialog，2026-10-03 裁定）→ 不可取消的进度遮罩 → 完成页（结果清单）。
struct AccountDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: AccountDeletionViewModel

    var body: some View {
        ZStack {
            switch self.viewModel.phase {
            case .completed(let outcome):
                self.completion(outcome)
            case .explaining, .deleting:
                self.explanation
            }

            if self.viewModel.isDeleting {
                self.progressOverlay
            }
        }
        .background(CatalogPalette.pageBackground)
        .navigationTitle(NSLocalizedString("account_deletion_entry", comment: "删除账号"))
        .navigationBarTitleDisplayMode(.inline)
        // 中文注释：删除中与完成后都不许返回：前者不可取消，后者只能点「好」回到访客状态的设置页。
        .navigationBarBackButtonHidden(self.viewModel.phase != .explaining)
        .toolbar(.hidden, for: .tabBar)
        .alert(
            NSLocalizedString("account_deletion_confirm_title", comment: "删除账号？"),
            isPresented: self.$viewModel.isConfirming
        ) {
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("account_deletion_entry", comment: "删除账号"), role: .destructive) {
                Task {
                    await self.viewModel.confirmDeletion()
                }
            }
        } message: {
            Text(NSLocalizedString("account_deletion_confirm_message", comment: "删除后无法恢复，接下来再做一次 Apple 验证"))
        }
        .alert(
            self.viewModel.failureAlert?.title ?? "",
            isPresented: self.failureAlertBinding
        ) {
            Button("OK", role: .cancel) {
                self.viewModel.failureAlert = nil
            }
        } message: {
            Text(self.viewModel.failureAlert?.message ?? "")
        }
    }

    // MARK: - 说明（第三节）

    private var explanation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AccountDeletionHeader(
                    symbol: "person.crop.circle.badge.xmark",
                    tone: .destructive,
                    title: NSLocalizedString("account_deletion_headline", comment: "删除你的 AnyPortal 账号"),
                    message: NSLocalizedString("account_deletion_intro", comment: "立即生效、无法撤销")
                )

                SettingsCardGroup(title: NSLocalizedString("account_deletion_section_deleted", comment: "会删除")) {
                    AccountDeletionInfoRow(
                        symbol: "person.crop.circle",
                        tone: .destructive,
                        title: NSLocalizedString("account_deletion_row_account_title", comment: "账号与登录信息"),
                        detail: NSLocalizedString("account_deletion_row_account_detail", comment: "账号及其与 Apple ID 的连结")
                    )
                    SettingsRowSeparator()
                    AccountDeletionInfoRow(
                        symbol: "circle.circle",
                        tone: .destructive,
                        title: NSLocalizedString("account_deletion_row_coins_title", comment: "coin 余额"),
                        detail: NSLocalizedString("account_deletion_row_coins_detail", comment: "没有现金价值，作废"),
                        trailingAmount: self.viewModel.coinBalance()
                    )
                    SettingsRowSeparator()
                    AccountDeletionInfoRow(
                        symbol: "list.bullet",
                        tone: .destructive,
                        title: NSLocalizedString("account_deletion_row_generations_title", comment: "生成记录"),
                        detail: NSLocalizedString("account_deletion_row_generations_detail", comment: "送出过的生成与结果清单")
                    )
                    SettingsRowSeparator()
                    AccountDeletionInfoRow(
                        symbol: "icloud",
                        tone: .destructive,
                        title: NSLocalizedString("account_deletion_row_device_title", comment: "本机与 iCloud 中的数据"),
                        detail: NSLocalizedString("account_deletion_row_device_detail", comment: "来源、收藏、历史、阅读进度与导入的书")
                    )
                    SettingsRowSeparator()
                    AccountDeletionInfoRow(
                        symbol: "key",
                        tone: .destructive,
                        title: NSLocalizedString("account_deletion_row_apple_title", comment: "通过 Apple 登录的授权"),
                        detail: NSLocalizedString("account_deletion_row_apple_detail", comment: "向 Apple 撤销登录授权")
                    )
                }

                SettingsCardGroup(title: NSLocalizedString("account_deletion_section_kept", comment: "会保留")) {
                    AccountDeletionInfoRow(
                        symbol: "bag",
                        tone: .neutral,
                        title: NSLocalizedString("account_deletion_row_purchases_title", comment: "已购项目"),
                        detail: NSLocalizedString("account_deletion_row_purchases_detail", comment: "跟随 App Store 账户，可恢复")
                    )
                    SettingsRowSeparator()
                    AccountDeletionInfoRow(
                        symbol: "doc.text",
                        tone: .neutral,
                        title: NSLocalizedString("account_deletion_row_rules_title", comment: "生成过的站点规则"),
                        detail: NSLocalizedString("account_deletion_row_rules_detail", comment: "保留供他人复用，已解除关联")
                    )
                }

                SettingsCardGroup(title: NSLocalizedString("account_deletion_section_notice", comment: "删除前请留意")) {
                    AccountDeletionInfoRow(
                        symbol: "clock",
                        tone: .warning,
                        title: NSLocalizedString("account_deletion_row_in_progress_title", comment: "进行中的生成"),
                        detail: NSLocalizedString("account_deletion_row_in_progress_detail", comment: "会完成但看不到结果")
                    )
                    SettingsRowSeparator()
                    AccountDeletionInfoRow(
                        symbol: "gift",
                        tone: .warning,
                        title: NSLocalizedString("account_deletion_row_resignup_title", comment: "之后重新注册"),
                        detail: NSLocalizedString("account_deletion_row_resignup_detail", comment: "12 个月内不再送新账号 coin")
                    )
                }

                SettingsCardGroup(title: NSLocalizedString("account_deletion_section_steps", comment: "接下来")) {
                    self.steps
                }

                Button(
                    action: {
                        self.viewModel.requestConfirmation()
                    },
                    label: {
                        Text(NSLocalizedString("account_deletion_continue", comment: "继续删除"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(CatalogPalette.onAction)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(CatalogPalette.destructive, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                )
                .buttonStyle(.plain)
                .disabled(self.viewModel.isDeleting)
                .padding(.horizontal, 20)
                .padding(.top, 28)

                Button(
                    action: {
                        self.dismiss()
                    },
                    label: {
                        Text(NSLocalizedString("account_deletion_keep", comment: "保留账号"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(CatalogPalette.settingsIcon)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                )
                .buttonStyle(.plain)
                .disabled(self.viewModel.isDeleting)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .padding(.bottom, 24)
        }
    }

    /// 中文注释：「接下来」三步：事先说明中途要再做一次 Apple 验证、取消验证什么都不删（第四节第 3 步）。
    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                self.step(1, NSLocalizedString("account_deletion_step_confirm", comment: "确认删除"))
                self.step(2, NSLocalizedString("account_deletion_step_apple", comment: "通过 Apple 验证"))
                self.step(3, NSLocalizedString("account_deletion_step_delete", comment: "删除并清除数据"))
            }
            Text(NSLocalizedString("account_deletion_steps_note", comment: "Apple 验证确认本人，取消不删任何东西"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private func step(_ number: Int, _ title: String) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: "\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CatalogPalette.onPrimary)
                .frame(width: 28, height: 28)
                .background(Color.primary, in: Circle())
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 进度遮罩（第四节）

    private var progressOverlay: some View {
        ZStack {
            CatalogPalette.pressedScrim
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(NSLocalizedString("account_deletion_progress", comment: "正在删除账号…"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(NSLocalizedString("account_deletion_progress_detail", comment: "一并清除本机与 iCloud，无法取消"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 22)
            .frame(width: 250)
            .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        // 中文注释：吞掉一切点击——删除不可取消。
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - 完成页（第八节）

    private func completion(_ outcome: AccountDeletionOutcome) -> some View {
        let items: [AccountDeletionViewModel.CompletionItem] = AccountDeletionViewModel.completionItems(for: outcome)
        var message: String = NSLocalizedString("account_deletion_done_message", comment: "账号与数据已删除，回到未登录")
        if items.contains(where: { $0.status != .done }) {
            message += NSLocalizedString("account_deletion_done_attention", comment: "还有下面几项需要留意")
        }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountDeletionHeader(
                        symbol: "checkmark",
                        tone: .success,
                        title: NSLocalizedString("account_deletion_done_title", comment: "账号已删除"),
                        message: message
                    )

                    SettingsCardGroup(
                        title: nil,
                        footer: NSLocalizedString("account_deletion_done_purchases_note", comment: "已购项目可恢复")
                    ) {
                        ForEach(Array(items.enumerated()), id: \.element.title) { index, item in
                            if index > 0 {
                                SettingsRowSeparator(leadingInset: 48)
                            }
                            AccountDeletionResultRow(item: item)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.bottom, 24)
            }

            Button(
                action: {
                    self.dismiss()
                },
                label: {
                    Text("OK")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(CatalogPalette.onAction)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(CatalogPalette.addAction, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            )
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private var failureAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.failureAlert != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.failureAlert = nil
                }
            }
        )
    }
}

// MARK: - 组件

/// 中文注释：本页图标的语气色：会删除用删除色、会保留用设置页图标蓝、请留意用警示色、完成用获得色。
private enum AccountDeletionTone {
    case destructive
    case neutral
    case warning
    case success

    var foreground: Color {
        switch self {
        case .destructive:
            return CatalogPalette.destructive
        case .neutral:
            return CatalogPalette.settingsIcon
        case .warning:
            return CatalogPalette.warning
        case .success:
            return CatalogPalette.gain
        }
    }

    /// 中文注释：图标底：同色浅色 12%、深色 24%（与 `settingsIconFill` 同一取法）。
    func fill(_ colorScheme: ColorScheme) -> Color {
        return self.foreground.opacity(colorScheme == .dark ? 0.24 : 0.12)
    }
}

/// 中文注释：页顶：56pt 圆形淡底图标 + 大标题 + 一句说明。说明页与完成页共用。
private struct AccountDeletionHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let tone: AccountDeletionTone
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: self.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(self.tone.foreground)
                .frame(width: 56, height: 56)
                .background(self.tone.fill(self.colorScheme), in: Circle())
                .accessibilityHidden(true)
            Text(self.title)
                .font(.title2.weight(.heavy))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            Text(self.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

/// 中文注释：说明卡的一行：32pt 圆角 9 图标块 + 标题 + 说明；coin 行在行尾用删除色大数字写余额，余额未知时不写。
private struct AccountDeletionInfoRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let tone: AccountDeletionTone
    let title: String
    let detail: String
    var trailingAmount: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: self.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(self.tone.foreground)
                .frame(width: 32, height: 32)
                .background(self.tone.fill(self.colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(self.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let amount: Int = self.trailingAmount {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: "\(amount)")
                        .font(.title2.weight(.heavy))
                        .monospacedDigit()
                    Text(NSLocalizedString("account_deletion_coin_unit", comment: "coin"))
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(CatalogPalette.destructive)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// 中文注释：完成页结果清单的一行：做完的打绿勾、右侧小字；要用户留意的换警示色图标与状态，下面附说明。
private struct AccountDeletionResultRow: View {
    let item: AccountDeletionViewModel.CompletionItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: self.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(self.item.status == .done ? CatalogPalette.gain : CatalogPalette.warning)
                .frame(width: 20, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(self.item.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(self.item.statusText)
                        .font(self.item.status == .done ? Font.footnote : Font.footnote.weight(.semibold))
                        .foregroundStyle(self.item.status == .done ? Color.secondary : CatalogPalette.warning)
                }
                if let detail: String = self.item.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch self.item.status {
        case .done:
            return "checkmark"
        case .needsAttention:
            return "exclamationmark.circle"
        case .waiting:
            return "clock"
        }
    }
}
