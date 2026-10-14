import SwiftUI

// 中文注释：删除账号页（docs/design/Account-Deletion-Design.md 第三、四、八节）：从设置页「删除账号」推进来。
// 说明四组 → 「继续」→ 系统居中确认框（不用 confirmationDialog，2026-10-03 裁定）→ 不可取消的进度遮罩 → 完成页。
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
            Text(NSLocalizedString("account_deletion_confirm_message", comment: "删除后无法恢复"))
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
                Text(NSLocalizedString("account_deletion_intro", comment: "删除立即生效、无法撤销"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                SettingsCardGroup(title: NSLocalizedString("account_deletion_section_deleted", comment: "将删除")) {
                    self.bulletRows([
                        NSLocalizedString("account_deletion_deleted_account", comment: "账号与登录信息"),
                        self.coinLine,
                        NSLocalizedString("account_deletion_deleted_generations", comment: "生成记录"),
                        NSLocalizedString("account_deletion_deleted_device_data", comment: "本机与 iCloud 中的数据")
                    ])
                }
                SettingsCardGroup(title: NSLocalizedString("account_deletion_section_kept", comment: "将保留")) {
                    self.bulletRows([NSLocalizedString("account_deletion_kept_rules", comment: "生成过的规则保留")])
                }
                SettingsCardGroup(title: NSLocalizedString("account_deletion_section_purchases", comment: "已购项目")) {
                    self.bulletRows([NSLocalizedString("account_deletion_purchases", comment: "可用同一 App Store 账户恢复")])
                }
                SettingsCardGroup(title: NSLocalizedString("account_deletion_section_generations", comment: "进行中的生成")) {
                    self.bulletRows([NSLocalizedString("account_deletion_generations", comment: "会完成但看不到结果")])
                }

                Button(
                    action: {
                        self.viewModel.requestConfirmation()
                    },
                    label: {
                        Text(NSLocalizedString("account_deletion_continue", comment: "继续"))
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
            }
            .padding(.bottom, 24)
        }
    }

    private var coinLine: String {
        guard let balance: Int = self.viewModel.coinBalance() else {
            return NSLocalizedString("account_deletion_deleted_coins", comment: "coin 余额作废")
        }
        return String(
            format: NSLocalizedString("account_deletion_deleted_coins_format", comment: "你的 N coin 作废"),
            balance
        )
    }

    private func bulletRows(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "•")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }

    // MARK: - 进度遮罩（第四节）

    private var progressOverlay: some View {
        ZStack {
            CatalogPalette.pressedScrim
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(NSLocalizedString("account_deletion_progress", comment: "正在删除账号…"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        // 中文注释：吞掉一切点击——删除不可取消。
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - 完成页（第八节）

    private func completion(_ outcome: AccountDeletionOutcome) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("account_deletion_done_title", comment: "账号已删除"))
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(NSLocalizedString("account_deletion_done_message", comment: "账号与数据已删除"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                let notes: [String] = AccountDeletionViewModel.completionNotes(for: outcome)
                if notes.isEmpty == false {
                    SettingsCardGroup(title: nil) {
                        self.bulletRows(notes)
                    }
                    .padding(.top, 8)
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
                .padding(.top, 28)
            }
            .padding(.bottom, 24)
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
