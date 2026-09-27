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
    @State private var didCopyAccountIdentifier: Bool = false
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
                Form {
                Section("Account") {
                    Button {
                        Task {
                            await self.viewModel.togglePortalAccount()
                        }
                    } label: {
                        SettingsRow(
                            image: "SettingsAccount",
                            title: self.viewModel.isPortalAuthenticated
                                ? NSLocalizedString("Sign Out of BrowseCraft", comment: "")
                                : NSLocalizedString("Sign in with Apple", comment: ""),
                            detail: self.viewModel.isPortalAuthenticated
                                ? NSLocalizedString("BrowseCraft account connected", comment: "")
                                : NSLocalizedString("Required for purchases and Cloud Sync", comment: "")
                        )
                    }
                    .disabled(self.viewModel.isPortalAccountActionInFlight)

                    if self.viewModel.isPortalAuthenticated,
                       let wallet: CoinWalletStore = self.viewModel.coinWalletStore {
                        // 中文注释：余额行点进去看流水（设计书 30.8）；服务端为准。
                        NavigationLink(
                            destination: CoinLedgerView(viewModel: wallet.makeLedgerViewModel())
                                .task {
                                    // 中文注释：进流水页时余额行一起对齐服务端。
                                    await wallet.refresh()
                                }
                        ) {
                            SettingsRow(
                                image: "SettingsPremium",
                                title: NSLocalizedString("coin_balance_row_title", comment: ""),
                                detail: Self.coinDetail(wallet)
                            )
                        }

                        // 中文注释：账户 ID，点一下复制；用户报给运营后可在服务器上手动加减 coin（用户 2026-09-27）。
                        Button(
                            action: {
                                UIPasteboard.general.string = wallet.accountIdentifier
                                self.didCopyAccountIdentifier = true
                            },
                            label: {
                                SettingsRow(
                                    image: "SettingsAccount",
                                    title: NSLocalizedString("account_id_row_title", comment: ""),
                                    detail: self.didCopyAccountIdentifier
                                        ? NSLocalizedString("account_id_copied", comment: "")
                                        : wallet.accountIdentifier
                                )
                            }
                        )
                        .buttonStyle(.plain)
                    }

                    NavigationLink(destination: CloudSyncSettingsView(
                        viewModel: self.cloudSyncViewModel
                    )) {
                        SettingsRow(
                            image: "SettingsCloudSync",
                            title: NSLocalizedString("Cloud Sync", comment: ""),
                            detail: self.cloudSyncDetail
                        )
                    }

                    NavigationLink(destination: BookmarksSettingsView()) {
                        SettingsRow(
                            image: "SettingsBookmarks",
                            title: NSLocalizedString("Bookmarks", comment: ""),
                            detail: NSLocalizedString("Favorites and saved items", comment: "")
                        )
                    }

                    Button(
                        action: {
                            var transaction: SwiftUI.Transaction = SwiftUI.Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                self.isShowingInAppPurchase = true
                            }
                        },
                        label: {
                            SettingsRow(
                                image: "SettingsPremium",
                                title: NSLocalizedString("Premium", comment: ""),
                                detail: NSLocalizedString("Unlock paid features", comment: "")
                            )
                        }
                    )
                    .buttonStyle(.plain)

                    Button(
                        action: {
                            Task {
                                await self.adPlaybackViewModel.loadAndShow(
                                    rewardCoordinator: self.rewardedAdRewardCoordinator
                                )
                            }
                        },
                        label: {
                            SettingsRow(
                                image: "SettingsAdService",
                                title: self.adPlaybackViewModel.isLoading ? NSLocalizedString("Starting Ad Service", comment: "") : NSLocalizedString("Start Ad Service", comment: ""),
                                detail: self.adServiceDetail
                            )
                        }
                    )
                    .disabled(self.adPlaybackViewModel.isLoading)

                    #if BROWSECRAFT_AD_TEST_TOOLS
                    // 中文注释：仅测试版。点一下申请跟踪授权、显示并复制本机 IDFA，拿去 AdMob「测试设备」登记。
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
                    .buttonStyle(.plain)
                    #endif
                }

                Section("Storage") {
                    NavigationLink(destination: CacheSettingsView(
                        selectedImageCacheLimit: self.imageCacheLimitBinding,
                        clearCacheAction: {
                            self.viewModel.clearImageCache()
                        }
                    )) {
                        SettingsRow(
                            image: "SettingsCache",
                            title: NSLocalizedString("Cache", comment: ""),
                            detail: self.viewModel.imageCacheSettings.displayTitle
                        )
                    }
                }

                Section(
                    content: {
                        Toggle(isOn: self.$isDiagnosticsEnabled) {
                            SettingsRow(
                                image: "SettingsCrashDiagnostics",
                                title: NSLocalizedString("Send Crash Diagnostics", comment: ""),
                                detail: self.isDiagnosticsEnabled ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: "")
                            )
                        }
                        .onChange(of: self.isDiagnosticsEnabled) { _, newValue in
                            CrashDiagnostics.shared.setCollectionEnabled(newValue)
                            AppAnalytics.shared.logSettingChanged(
                                name: "crash_diagnostics",
                                value: String(newValue)
                            )
                        }

                        SettingsRow(
                            image: "SettingsDiagnosticCode",
                            title: NSLocalizedString("Diagnostic Code", comment: ""),
                            detail: self.viewModel.diagnosticCode
                        )
                        .contextMenu {
                            Button("Copy") {
                                UIPasteboard.general.string = self.viewModel.diagnosticCode
                            }
                        }

                        Button(
                            action: {
                                UIPasteboard.general.string = self.viewModel.diagnosticCode
                            },
                            label: {
                                SettingsRow(
                                    image: "SettingsCopy",
                                    title: NSLocalizedString("Copy Diagnostic Code", comment: ""),
                                    detail: nil
                                )
                            }
                        )
                        .buttonStyle(.plain)
                    },
                    footer: {
                        Text("Diagnostic reports include the code above, app version, device model, current screen, source, stage, and selected non-crash errors. They do not include cookies, tokens, full HTML, or full URL query values.")
                    }
                )

                Section("App") {
                    SettingsRow(
                        image: "SettingsVersion",
                        title: NSLocalizedString("Version", comment: ""),
                        detail: Self.versionText
                    )

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
                                detail: nil
                            )
                        }
                    )
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Settings")
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

    /// 中文注释：余额与「看一次广告 +N」并排；价格由服务端下发。
    /// 中文注释：余额行只显示余额；「看完一次广告 +N」放在「啟動廣告服務」那一行后面（用户 2026-09-27）。
    private static func coinDetail(_ wallet: CoinWalletStore) -> String {
        if let value: Int = wallet.balance {
            return String(format: NSLocalizedString("coin_balance_detail", comment: ""), value)
        }
        return NSLocalizedString("coin_balance_unknown", comment: "")
    }

    private var adServiceDetail: String? {
        if self.adPlaybackViewModel.isLoading {
            return NSLocalizedString("Loading", comment: "")
        }
        guard self.viewModel.isPortalAuthenticated,
              let wallet: CoinWalletStore = self.viewModel.coinWalletStore else {
            return nil
        }
        return String(format: NSLocalizedString("coin_earn_detail", comment: ""), wallet.pricing.adReward)
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
