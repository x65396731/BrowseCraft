import StoreKit
import SwiftUI
import UIKit

// 中文注释：SettingsView.swift 属于用户设置功能层，集中承载账号、同步、缓存和应用信息入口。

/// 中文注释：SettingsView 是应用的用户设置页。
struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var viewModel: SettingsViewModel
    @Bindable private var cloudSyncViewModel: CloudSyncSettingsViewModel
    @State private var adPlaybackViewModel: AdPlaybackViewModel = AdPlaybackViewModel()
    @Environment(\.rewardedAdRewardCoordinator) private var rewardedAdRewardCoordinator
    @AppStorage(CrashDiagnostics.collectionEnabledDefaultsKey) private var isDiagnosticsEnabled: Bool = CrashDiagnostics.isCollectionEnabled

    @State private var isShowingInAppPurchase: Bool = false
    @State private var isConfirmingSignOut: Bool = false
    /// 刚复制的是哪一行；说明换成「已复制」约 2 秒后恢复。
    @State private var copiedField: CopiedField?
    #if BROWSECRAFT_AD_TEST_TOOLS
    @State private var adTestIDFADetail: String?
    #endif

    init(
        viewModel: SettingsViewModel,
        cloudSyncViewModel: CloudSyncSettingsViewModel
    ) {
        self.viewModel = viewModel
        self.cloudSyncViewModel = cloudSyncViewModel
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Settings")
                            .font(.largeTitle.weight(.heavy))
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        SettingsAccountCardView(
                            isSignedIn: self.viewModel.isPortalAuthenticated,
                            isAccountActionInFlight: self.viewModel.isPortalAccountActionInFlight,
                            wallet: self.viewModel.coinWalletStore,
                            isAdLoading: self.adPlaybackViewModel.isLoading,
                            signInAction: {
                                Task {
                                    await self.viewModel.togglePortalAccount()
                                }
                            },
                            watchAdAction: {
                                Task {
                                    await self.adPlaybackViewModel.loadAndShow(
                                        rewardCoordinator: self.rewardedAdRewardCoordinator
                                    )
                                }
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        // 中文注释：高级版入口卡与来源页「更多位置」打开的是同一个购买页。
                        SourcesEntryCardView(
                            title: NSLocalizedString("Premium", comment: ""),
                            message: NSLocalizedString("settings_premium_detail", comment: "高级版说明"),
                            systemImage: "sparkles",
                            iconForeground: .white,
                            iconBackground: CatalogPalette.addAction,
                            action: {
                                self.presentInAppPurchase()
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        self.syncAndStorageGroup
                        self.privacyAndDiagnosticsGroup
                        self.aboutGroup

                        #if BROWSECRAFT_AD_TEST_TOOLS
                        self.testToolsGroup
                        #endif

                        if self.viewModel.isPortalAuthenticated {
                            self.signOutButton
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .background(CatalogPalette.pageBackground)
                .toolbar(.hidden, for: .navigationBar)
                .refreshable {
                    await self.viewModel.refreshPortalAccountStatus()
                    await self.viewModel.coinWalletStore?.refresh()
                }
                // 中文注释：用系统居中提示框，不用 confirmationDialog——iOS 26 上后者变成指向按钮的气泡，用户觉得奇怪（2026-10-03 裁定）。
                .alert(
                    NSLocalizedString("settings_sign_out_confirm_title", comment: "退出确认框标题"),
                    isPresented: self.$isConfirmingSignOut
                ) {
                    Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
                    Button(NSLocalizedString("Sign Out of BrowseCraft", comment: ""), role: .destructive) {
                        Task {
                            await self.viewModel.togglePortalAccount()
                        }
                    }
                } message: {
                    Text(NSLocalizedString("settings_sign_out_confirm_message", comment: "退出确认框说明"))
                }
                .alert("Cache", isPresented: self.cacheStatusAlertBinding) {
                    Button("OK", role: .cancel) {
                        self.viewModel.cacheStatusMessage = nil
                    }
                } message: {
                    Text(self.viewModel.cacheStatusMessage ?? "")
                }
                .alert("Cache Settings", isPresented: self.cacheErrorAlertBinding) {
                    Button("OK", role: .cancel) {
                        self.viewModel.cacheErrorMessage = nil
                    }
                } message: {
                    Text(self.viewModel.cacheErrorMessage ?? "")
                }
                .alert("Google Ads", isPresented: self.adAlertBinding) {
                    Button("OK") {
                        self.adPlaybackViewModel.message = nil
                    }
                } message: {
                    Text(self.adPlaybackViewModel.message ?? "")
                }
                .onAppear {
                    self.viewModel.refreshDiagnosticCode()
                    Task {
                        await self.viewModel.refreshPortalAccountStatus()
                    }
                    // 中文注释：余额以服务端为准，运营手动加减 coin 不会推送到 App——设置页每次出现都拉一次，
                    // 不然只能等下次启动或回到前台（用户 2026-09-27：加了 10000 后设置页没刷新）。
                    Task {
                        await self.viewModel.coinWalletStore?.refresh()
                    }
                    CrashDiagnostics.shared.setScreen(.settings)
                    AppAnalytics.shared.logScreenView(.settings)
                }
                .alert(
                    "BrowseCraft Account",
                    isPresented: self.portalAccountErrorAlertBinding
                ) {
                    Button("OK", role: .cancel) {
                        self.viewModel.portalAccountErrorMessage = nil
                    }
                } message: {
                    Text(self.viewModel.portalAccountErrorMessage ?? "")
                }
            }
            .allowsHitTesting(self.isShowingInAppPurchase == false)
            .accessibilityHidden(self.isShowingInAppPurchase)

            if self.isShowingInAppPurchase {
                InAppPurchaseSheetView(
                    authorizeStoreKitAction: {
                        return try await self.viewModel
                            .authorizeUserInitiatedStoreKitAction()
                    },
                    validateAuthorizedUser: { userID in
                        try await self.viewModel
                            .validateAuthorizedStoreKitUser(userID)
                    },
                    applyPurchaseAction: { transaction, signedTransaction, plan in
                        return try await self.viewModel.submitStoreKitPurchase(
                            transaction: transaction,
                            signedTransaction: signedTransaction,
                            plan: plan
                        )
                    },
                    restorePurchasesAction: { userID in
                        try await self.viewModel.restoreStoreKitPurchases(
                            for: userID
                        )
                    },
                    transactionUpdateRevision:
                        self.viewModel.storeKitTransactionUpdateRevision,
                    transactionUpdateActiveProductIDs:
                        self.viewModel
                            .storeKitTransactionUpdateActiveProductIDs,
                    closeAction: {
                        var transaction: SwiftUI.Transaction = SwiftUI.Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.isShowingInAppPurchase = false
                        }
                    }
                )
                .background(Color.black.ignoresSafeArea())
                .transition(.identity)
                .zIndex(1)
            }
        }
        .toolbar(
            self.isShowingInAppPurchase ? .hidden : .visible,
            for: .tabBar
        )
        .onChange(of: self.viewModel.isInAppPurchaseRequested, initial: true) { _, isRequested in
            // 中文注释：来源页「更多位置」切到本页并请求打开购买入口；`initial` 覆盖本页首次出现的情形。
            guard isRequested else {
                return
            }
            self.viewModel.consumeInAppPurchaseRequest()
            self.presentInAppPurchase()
        }
    }

    // MARK: - 分组（设计文档第二节）

    private var syncAndStorageGroup: some View {
        SettingsCardGroup(title: NSLocalizedString("settings_section_sync_storage", comment: "分组：同步与存储")) {
            NavigationLink(destination: CloudSyncSettingsView(
                viewModel: self.cloudSyncViewModel
            )) {
                SettingsRow(
                    image: "SettingsCloudSync",
                    title: NSLocalizedString("Cloud Sync", comment: ""),
                    detail: self.cloudSyncDetail,
                    accessory: .chevron
                )
            }
            .buttonStyle(SettingsRowButtonStyle())

            SettingsRowSeparator()

            NavigationLink(destination: CacheSettingsView(
                selectedImageCacheLimit: self.imageCacheLimitBinding,
                clearCacheAction: {
                    self.viewModel.clearImageCache()
                }
            )) {
                SettingsRow(
                    image: "SettingsCache",
                    title: NSLocalizedString("Cache", comment: ""),
                    detail: self.viewModel.imageCacheSettings.displayTitle,
                    accessory: .chevron
                )
            }
            .buttonStyle(SettingsRowButtonStyle())
        }
    }

    private var privacyAndDiagnosticsGroup: some View {
        SettingsCardGroup(
            title: NSLocalizedString("settings_section_privacy_diagnostics", comment: "分组：隐私与诊断"),
            footer: NSLocalizedString("Diagnostic reports include the code above, app version, device model, current screen, source, stage, and selected non-crash errors. They do not include cookies, tokens, full HTML, or full URL query values.", comment: "")
        ) {
            SettingsToggleRow(
                image: "SettingsCrashDiagnostics",
                title: NSLocalizedString("Send Crash Diagnostics", comment: ""),
                isOn: self.$isDiagnosticsEnabled
            )
            .onChange(of: self.isDiagnosticsEnabled) { _, newValue in
                CrashDiagnostics.shared.setCollectionEnabled(newValue)
                AppAnalytics.shared.logSettingChanged(
                    name: "crash_diagnostics",
                    value: String(newValue)
                )
            }

            SettingsRowSeparator()

            // 中文注释：点一下即复制；原来单独的「复制诊断码」行并进这里。
            Button(
                action: {
                    self.copy(self.viewModel.diagnosticCode, field: .diagnosticCode)
                },
                label: {
                    SettingsRow(
                        image: "SettingsDiagnosticCode",
                        title: NSLocalizedString("Diagnostic Code", comment: ""),
                        detail: self.copiedField == .diagnosticCode
                            ? NSLocalizedString("settings_copied", comment: "已复制")
                            : self.viewModel.diagnosticCode,
                        isDetailHighlighted: self.copiedField == .diagnosticCode
                    )
                }
            )
            .buttonStyle(SettingsRowButtonStyle())
        }
    }

    private var aboutGroup: some View {
        SettingsCardGroup(title: NSLocalizedString("settings_section_about", comment: "分组：关于")) {
            SettingsRow(
                image: "SettingsVersion",
                title: NSLocalizedString("Version", comment: ""),
                detail: Self.versionText
            )

            SettingsRowSeparator()

            Button(
                action: {
                    guard let writeReviewURL: URL = Self.writeReviewURL else {
                        return
                    }
                    self.openURL(writeReviewURL)
                },
                label: {
                    SettingsRow(
                        image: "SettingsRate",
                        title: NSLocalizedString("Rate AnyPortal", comment: ""),
                        accessory: .chevron
                    )
                }
            )
            .buttonStyle(SettingsRowButtonStyle())

            // 中文注释：账号 ID 只在报给运营时用（运营据此在服务器上手动加减 coin），所以放在「关于」，
            // 只显示前 8 位，点一下复制完整 ID。
            if self.viewModel.isPortalAuthenticated,
               let wallet: CoinWalletStore = self.viewModel.coinWalletStore {
                SettingsRowSeparator()

                Button(
                    action: {
                        self.copy(wallet.accountIdentifier, field: .accountIdentifier)
                    },
                    label: {
                        SettingsRow(
                            image: "SettingsAccount",
                            title: NSLocalizedString("account_id_row_title", comment: ""),
                            detail: self.copiedField == .accountIdentifier
                                ? NSLocalizedString("settings_copied", comment: "已复制")
                                : Self.shortIdentifier(wallet.accountIdentifier),
                            isDetailHighlighted: self.copiedField == .accountIdentifier
                        )
                    }
                )
                .buttonStyle(SettingsRowButtonStyle())
            }
        }
    }

    #if BROWSECRAFT_AD_TEST_TOOLS
    // 中文注释：仅测试版。点一下申请跟踪授权、显示并复制本机 IDFA，拿去 AdMob「测试设备」登记。
    private var testToolsGroup: some View {
        SettingsCardGroup(title: NSLocalizedString("settings_section_test_tools", comment: "分组：测试工具")) {
            Button(
                action: {
                    Task {
                        let result = await AdTestDeviceTools.requestIDFA()
                        switch result {
                        case .available(let idfa):
                            UIPasteboard.general.string = idfa
                            self.adTestIDFADetail = String(
                                format: NSLocalizedString("ad_test_idfa_copied", comment: ""),
                                idfa
                            )
                        case .denied:
                            self.adTestIDFADetail = NSLocalizedString("ad_test_idfa_denied", comment: "")
                        case .trackingRestricted:
                            self.adTestIDFADetail = NSLocalizedString("ad_test_idfa_restricted", comment: "")
                        }
                    }
                },
                label: {
                    SettingsRow(
                        image: "SettingsAdService",
                        title: NSLocalizedString("ad_test_idfa_title", comment: ""),
                        detail: self.adTestIDFADetail ?? NSLocalizedString("ad_test_idfa_hint", comment: "")
                    )
                }
            )
            .buttonStyle(SettingsRowButtonStyle())
        }
    }
    #endif

    /// 退出登录单独一张卡片放最下，红字；点后先弹确认框（用户裁定：退出后购买、云同步与 coin 都不可用，没法用撤销恢复）。
    private var signOutButton: some View {
        Button(
            action: {
                self.isConfirmingSignOut = true
            },
            label: {
                HStack(spacing: 8) {
                    if self.viewModel.isPortalAccountActionInFlight {
                        ProgressView()
                    }
                    Text(NSLocalizedString("Sign Out of BrowseCraft", comment: ""))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(CatalogPalette.destructive)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        )
        .buttonStyle(.plain)
        .disabled(self.viewModel.isPortalAccountActionInFlight)
    }

    // MARK: - 动作

    private enum CopiedField: Equatable {
        case diagnosticCode
        case accountIdentifier
    }

    private func copy(_ value: String, field: CopiedField) {
        UIPasteboard.general.string = value
        self.copiedField = field
        Task {
            try? await Task.sleep(for: .seconds(2))
            if self.copiedField == field {
                self.copiedField = nil
            }
        }
    }

    private func presentInAppPurchase() {
        var transaction: SwiftUI.Transaction = SwiftUI.Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.isShowingInAppPurchase = true
        }
    }

    /// 账号 ID 是小写 UUID，行上只显示前 8 位。
    private static func shortIdentifier(_ identifier: String) -> String {
        guard identifier.count > 8 else {
            return identifier
        }
        return String(identifier.prefix(8)) + "…"
    }

    private var imageCacheLimitBinding: Binding<ImageCacheLimitOption> {
        return Binding<ImageCacheLimitOption>(
            get: {
                return self.viewModel.imageCacheSettings.limit
            },
            set: { newLimit in
                self.viewModel.selectImageCacheLimit(newLimit)
            }
        )
    }

    private var cacheErrorAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.cacheErrorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.cacheErrorMessage = nil
                }
            }
        )
    }

    private var portalAccountErrorAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.portalAccountErrorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.portalAccountErrorMessage = nil
                }
            }
        )
    }

    private var cacheStatusAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.cacheStatusMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.cacheStatusMessage = nil
                }
            }
        )
    }

    private var adAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.adPlaybackViewModel.message != nil
            },
            set: { newValue in
                if newValue == false {
                    self.adPlaybackViewModel.message = nil
                }
            }
        )
    }

    private static var versionText: String {
        let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private static let writeReviewURL: URL? = URL(
        string: "https://apps.apple.com/app/id6792714387?action=write-review"
    )

    private var cloudSyncDetail: String {
        switch self.cloudSyncViewModel.accountAvailability {
        case .notChecked:
            return NSLocalizedString("Off", comment: "")
        case .checking:
            return NSLocalizedString("Checking", comment: "")
        case .available:
            return self.cloudSyncViewModel.isCloudSyncEnabled ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: "")
        case .noAccount:
            return NSLocalizedString("Sign In Required", comment: "")
        case .restricted:
            return NSLocalizedString("Restricted", comment: "")
        case .temporarilyUnavailable:
            return NSLocalizedString("Temporarily Unavailable", comment: "")
        case .couldNotDetermine:
            return NSLocalizedString("Unavailable", comment: "")
        }
    }
}
