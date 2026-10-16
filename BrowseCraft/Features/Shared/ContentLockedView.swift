import SwiftUI

// 中文注释：收藏页与历史页共用的锁定态（`docs/design/Content-Lock-Design.md` 第三节）。
// 只留自绘大标题，不露数量、筛选与列表；中间是验证方式的圆标、标题、说明与解锁按钮。

struct ContentLockedView: View {
    let store: ContentLockStore
    /// 页面大标题（「收藏」「历史」），与未锁定时同一个本地化键。
    let pageTitle: LocalizedStringKey
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(self.pageTitle)
                    .font(.largeTitle.weight(.heavy))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    Image(systemName: self.store.method.lockSymbolName)
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(CatalogPalette.settingsIcon)
                        .frame(width: 88, height: 88)
                        .background(CatalogPalette.settingsIconFill, in: Circle())
                        .accessibilityHidden(true)

                    Text(self.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)

                    Text(self.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    if self.store.didLastUnlockFail && self.store.isAuthenticating == false {
                        self.failureNotice
                            .padding(.top, 20)
                    }

                    self.unlockButton
                        .padding(.top, self.store.didLastUnlockFail ? 16 : 28)
                }
                .padding(.horizontal, 40)
                .padding(.top, 120)
                .padding(.bottom, 24)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // 中文注释：盖在整页之上，底色要铺到状态栏下面，否则下层列表会从顶部露出来。
        .background(CatalogPalette.pageBackground.ignoresSafeArea())
    }

    private var failureNotice: some View {
        Label(NSLocalizedString("content_lock_failed", comment: "没有通过验证"), systemImage: "exclamationmark.circle")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(CatalogPalette.warning)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(CatalogPalette.warningFill, in: Capsule())
    }

    private var unlockButton: some View {
        Button(
            action: {
                Task {
                    await self.store.unlock(
                        reason: NSLocalizedString("content_lock_reason_unlock", comment: "解锁时的验证说明")
                    )
                }
            },
            label: {
                HStack(spacing: 8) {
                    if self.store.isAuthenticating {
                        ProgressView()
                            .tint(CatalogPalette.onAction)
                        Text(NSLocalizedString("content_lock_authenticating", comment: "正在验证"))
                    } else {
                        Image(systemName: self.store.method.lockSymbolName)
                            .accessibilityHidden(true)
                        Text(self.store.method.unlockButtonTitle)
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(CatalogPalette.onAction)
                .padding(.horizontal, 28)
                .frame(minHeight: 50)
                .background(CatalogPalette.addAction, in: Capsule())
                .opacity(self.store.isAuthenticating ? 0.6 : 1)
                .contentShape(Capsule())
            }
        )
        .buttonStyle(.plain)
        .disabled(self.store.isAuthenticating)
    }
}

// MARK: - 随验证方式变化的写法（设计文档第 2.2 节）

extension DeviceOwnerAuthenticationMethod {
    /// 生物识别的名称；只有锁屏密码或无法验证时为 nil。
    private var biometricName: String? {
        switch self {
        case .faceID:
            return NSLocalizedString("content_lock_method_face_id", comment: "面容 ID")
        case .touchID:
            return NSLocalizedString("content_lock_method_touch_id", comment: "触控 ID")
        case .opticID:
            return NSLocalizedString("content_lock_method_optic_id", comment: "Optic ID")
        case .passcode, .unavailable:
            return nil
        }
    }

    /// 锁定态圆标与解锁按钮上的 SF Symbol。
    var lockSymbolName: String {
        switch self {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .passcode, .unavailable:
            return "lock.fill"
        }
    }

    var unlockButtonTitle: String {
        guard let name: String = self.biometricName else {
            return NSLocalizedString("content_lock_unlock_passcode", comment: "使用密码解锁")
        }
        return String(format: NSLocalizedString("content_lock_unlock_biometric", comment: "使用某生物识别解锁"), name)
    }

    /// 设置页行图标：资产里的 22pt 模板图。
    var settingsImage: String {
        switch self {
        case .faceID:
            return "SettingsFaceID"
        case .touchID:
            return "SettingsTouchID"
        case .opticID:
            return "SettingsOpticID"
        case .passcode, .unavailable:
            return "SettingsPasscode"
        }
    }

    var settingsRowTitle: String {
        guard let name: String = self.biometricName else {
            return NSLocalizedString("content_lock_row_title_passcode", comment: "密码锁定")
        }
        return String(format: NSLocalizedString("content_lock_row_title_biometric", comment: "某生物识别锁定"), name)
    }

    var settingsFooter: String {
        if self == .unavailable {
            return NSLocalizedString("content_lock_footer_unavailable", comment: "没有锁屏密码时的说明")
        }
        guard let name: String = self.biometricName else {
            return NSLocalizedString("content_lock_footer_passcode", comment: "只有锁屏密码时的说明")
        }
        return String(format: NSLocalizedString("content_lock_footer_biometric", comment: "有生物识别时的说明"), name)
    }
}
