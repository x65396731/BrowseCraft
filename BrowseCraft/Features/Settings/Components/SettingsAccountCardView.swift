import SwiftUI

/// 设置页顶部的账号卡（`docs/design/Settings-Page-Redesign-Design.md` 第三节）。
///
/// 中文注释：已登录时是「账号 + coin 余额 + 看广告 +N + coin 流水」，看完广告就在按钮旁边看到余额变化；
/// 未登录时是插画 + 系统登录按钮 + 不计奖励的「看广告」（用户裁定：未登录能看，但不计 coin）。
/// 卡片用卡片色底，不用深色色块——账号不是内容类型。
struct SettingsAccountCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let isSignedIn: Bool
    let isAccountActionInFlight: Bool
    let wallet: CoinWalletStore?
    let isAdLoading: Bool
    let signInAction: () -> Void
    let watchAdAction: () -> Void

    var body: some View {
        Group {
            if self.isSignedIn {
                self.signedInContent
            } else {
                self.signedOutContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatalogPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - 已登录

    private var signedInContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CatalogPalette.settingsIcon)
                    .frame(width: 44, height: 44)
                    .background(CatalogPalette.settingsIconFill, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("settings_account_title", comment: "账号卡标题"))
                        .font(.subheadline.weight(.semibold))
                    Text(NSLocalizedString("settings_account_signed_in_with_apple", comment: "账号卡说明"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("coin_balance_row_title", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: self.balanceText)
                            .font(.title.weight(.heavy))
                            .monospacedDigit()
                            .lineLimit(1)
                        Text(verbatim: "coin")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 8)

                self.watchAdButton(isProminent: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if let wallet: CoinWalletStore = self.wallet {
                Divider()
                    .padding(.horizontal, 16)

                NavigationLink(
                    destination: CoinLedgerView(viewModel: wallet.makeLedgerViewModel(), wallet: wallet)
                        .task {
                            // 中文注释：进流水页时余额一起对齐服务端。
                            await wallet.refresh()
                        }
                ) {
                    HStack {
                        Text(NSLocalizedString("coin_ledger_title", comment: "coin 流水"))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsRowButtonStyle())
            }
        }
    }

    /// 余额未知（还没同步过）时大数字写「—」。
    private var balanceText: String {
        guard let balance: Int = self.wallet?.balance else {
            return "—"
        }
        return String(balance)
    }

    // MARK: - 未登录

    private var signedOutContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image("SettingsSignIn")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 66, height: 108)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("settings_sign_in_title", comment: "未登录账号卡标题"))
                        .font(.headline)
                    Text(NSLocalizedString("settings_sign_in_detail", comment: "未登录账号卡说明"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if self.isAccountActionInFlight {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(NSLocalizedString("settings_signing_in", comment: "正在登录"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 44)
                    } else {
                        // 中文注释：Apple 登录按钮只有系统给的黑 / 白两种样式，功能性取值（调色板登记的例外）。
                        AppleSignInButton(
                            style: self.colorScheme == .dark ? .white : .black,
                            action: self.signInAction
                        )
                        .id(self.colorScheme)
                        .frame(maxWidth: 240)
                        .frame(height: 44)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .padding(.leading, 12)
            .padding(.trailing, 16)

            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                self.watchAdButton(isProminent: false)
                Text(NSLocalizedString("settings_watch_ad_no_reward", comment: "未登录看完不计 coin"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 看广告

    /// 已登录是实心添加蓝「看广告 +N」，未登录是描边「看广告」。加载中换成转圈 +「加载中」并禁用。
    private func watchAdButton(isProminent: Bool) -> some View {
        let foreground: Color = isProminent ? CatalogPalette.onAction : CatalogPalette.settingsIcon
        return Button(action: self.watchAdAction) {
            HStack(spacing: 6) {
                if self.isAdLoading {
                    ProgressView()
                        .tint(foreground)
                    Text(NSLocalizedString("Loading", comment: ""))
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                    Text(isProminent ? self.prominentWatchAdTitle : NSLocalizedString("settings_watch_ad", comment: "看广告"))
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background {
                if isProminent {
                    Capsule().fill(CatalogPalette.addAction)
                } else {
                    Capsule().strokeBorder(CatalogPalette.addAction, lineWidth: 1.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        // 中文注释：禁用态系统已经压暗一层，不再叠加透明度——叠两层后深色模式下「加载中」几乎看不见（模拟器走查）。
        .disabled(self.isAdLoading)
    }

    /// +N 取服务端下发的 `pricing.adReward`；还拿不到正数时只写「看广告」。
    private var prominentWatchAdTitle: String {
        guard let reward: Int = self.wallet?.pricing.adReward, reward > 0 else {
            return NSLocalizedString("settings_watch_ad", comment: "看广告")
        }
        return String(format: NSLocalizedString("settings_watch_ad_reward", comment: "看广告 +N"), reward)
    }
}
