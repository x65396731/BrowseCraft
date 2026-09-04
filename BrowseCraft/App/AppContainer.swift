import BrowseCraftDomain
import CloudKit
import Foundation
import StoreKit

/// 中文注释：应用 Composition Root。它自身不再逐个装配对象，只组合三个子容器
/// （账户 / 规则运行时 / Feature），并持有跨页面的 App 生命周期职责：
/// StoreKit 交易监听、图片缓存配置，以及 Debug 专用的 runtime audit 入口。
@MainActor
final class AppContainer {
    private static let cloudKitContainerIdentifier: String = "iCloud.com.xiefei.AnyPortal"

    private let account: AccountComposition
    private let runtime: SourceRuntimeComposition
    private let features: FeatureComposition
    private let imageCacheConfigurator: ImageCacheConfigurator
    private var storeKitTransactionUpdatesTask: Task<Void, Never>?

    #if DEBUG
    /// 中文注释：显式 runtime audit 入口（BC-EVIDENCE-076.2）；无 launch environment 时完全惰性。
    private let videoRuntimeAuditLauncher: VideoRuntimeAuditLauncher
    /// 中文注释：BC-EVIDENCE-077.1——audit 的前台 WebUI 承载者，由根视图覆盖层观察；无 audit 时空闲。
    let videoRuntimeAuditWebUIPresenter: VideoRuntimeAuditWebUIPresenter
    #endif

    var browserRequestHeaderProvider: any BrowserRequestHeaderProviding {
        return self.runtime.browserRequestHeaderProvider
    }

    var systemCookieHeaderProvider: any SystemCookieHeaderProviding {
        return self.runtime.systemCookieHeaderProvider
    }

    init(bootstrap: AppBootstrapDependencies) throws {
        let imageCacheConfigurator: ImageCacheConfigurator = ImageCacheConfigurator()
        self.imageCacheConfigurator = imageCacheConfigurator

        let account: AccountComposition = AccountComposition(
            database: bootstrap.database,
            activeUserID: bootstrap.activeUserID,
            cloudKitContainerIdentifier: Self.cloudKitContainerIdentifier
        )
        self.account = account

        let runtime: SourceRuntimeComposition = SourceRuntimeComposition(
            sourceRepository: account.sourceRepository
        )
        self.runtime = runtime

        self.features = FeatureComposition(
            database: bootstrap.database,
            account: account,
            runtime: runtime,
            imageCacheConfigurator: imageCacheConfigurator
        )

        #if DEBUG
        // 中文注释：audit launcher 与正常视频链共用同一 pageLoader/parser/credential 组件，
        // 不建第二套装配（BC-EVIDENCE-076.1）。
        let videoRuntimeAuditWebUIPresenter: VideoRuntimeAuditWebUIPresenter =
            VideoRuntimeAuditWebUIPresenter()
        self.videoRuntimeAuditWebUIPresenter = videoRuntimeAuditWebUIPresenter
        self.videoRuntimeAuditLauncher = VideoRuntimeAuditLauncher(
            runtimeFactory: SourceRuntimeComposition.makeVideoRuntimeFactory(
                pageLoader: runtime.pageLoader,
                sourceCredentialStore: runtime.sourceCredentialStore
            ),
            webUIObserver: videoRuntimeAuditWebUIPresenter,
            browserRequestHeaderProvider: runtime.browserRequestHeaderProvider
        )
        #endif

        self.configureImageCache()
    }

    deinit {
        self.storeKitTransactionUpdatesTask?.cancel()
    }

    @MainActor
    func startApplicationServices() async {
        self.startStoreKitTransactionUpdatesListener()
        #if DEBUG
        // 中文注释：显式 runtime audit 只在 launch environment 齐备时运行，独立于其他服务，
        // 不阻塞正常启动路径（BC-EVIDENCE-076.2）。
        let videoRuntimeAuditLauncher: VideoRuntimeAuditLauncher = self.videoRuntimeAuditLauncher
        Task {
            await videoRuntimeAuditLauncher.runIfRequested()
        }
        #endif
        async let portalSession: Void = self.account.portalSessionCoordinator.start()
        async let cloudAccount: Void = self.account.startCloudAccountMonitoring()
        _ = await (portalSession, cloudAccount)
    }

    func handleAppBecameActive() async {
        async let portalSession: Void = self.account.portalSessionCoordinator.handleAppBecameActive()
        async let cloudSync: Void = self.account.cloudSyncCoordinator.requestSync(trigger: .foreground)
        _ = await (portalSession, cloudSync)
    }

    func handleCloudRemoteNotification() async throws -> CloudSyncRunResult {
        return try await self.account.cloudSyncCoordinator.synchronize(trigger: .remoteNotification)
    }

    func makeSourcesViewModel() -> SourcesViewModel {
        return self.features.sourcesFeatureFactory.makeViewModel()
    }

    func makeLibraryViewModel() -> LibraryViewModel {
        return self.features.libraryFeatureFactory.makeViewModel()
    }

    func makeFavoritesViewModel() -> FavoritesViewModel {
        return self.features.favoritesFeatureFactory.makeViewModel()
    }

    func makeHistoryViewModel() -> HistoryViewModel {
        return self.features.historyFeatureFactory.makeViewModel()
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        return self.features.settingsViewModel
    }

    @MainActor
    func makeCloudSyncSettingsViewModel() -> CloudSyncSettingsViewModel {
        return self.features.settingsFeatureFactory.makeCloudSyncViewModel()
    }

    func makeLibraryContentViewModelFactory() -> LibraryContentViewModelFactory {
        return self.features.makeLibraryContentViewModelFactory()
    }

    @MainActor
    private func startStoreKitTransactionUpdatesListener() {
        guard self.storeKitTransactionUpdatesTask == nil else {
            return
        }

        IAPDiagnostics.notice("event=transaction-updates-listener-started")
        self.storeKitTransactionUpdatesTask = Task { @MainActor [weak self] in
            for await verification in StoreKit.Transaction.updates {
                guard Task.isCancelled == false,
                      let self else {
                    return
                }
                await self.processStoreKitTransactionUpdate(verification)
            }
        }
    }

    @MainActor
    private func processStoreKitTransactionUpdate(
        _ verification: VerificationResult<StoreKit.Transaction>
    ) async {
        var activeProductIDs: Set<String>?
        defer {
            self.features.settingsViewModel.recordStoreKitTransactionUpdate(
                activeProductIDs: activeProductIDs
            )
        }

        switch verification {
        case .unverified(let transaction, let error):
            IAPDiagnostics.error(
                "event=transaction-update-rejected reason=unverified " +
                    "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id)) " +
                    "error=\(IAPDiagnostics.safeErrorCode(error))"
            )
        case .verified(let transaction):
            guard let plan: InAppPurchasePlan =
                InAppPurchasePlan.plansByProductID[transaction.productID],
                  plan.isRestorable else {
                IAPDiagnostics.error(
                    "event=transaction-update-rejected reason=unsupported-product " +
                        "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id)) " +
                        "productID=\(transaction.productID)"
                )
                return
            }

            IAPDiagnostics.notice(
                "event=transaction-update-received " +
                    "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id)) " +
                    "productID=\(transaction.productID) " +
                    "environment=\(transaction.environment.rawValue) " +
                    "isRevoked=\(transaction.revocationDate != nil)"
            )
            await self.account.portalSessionCoordinator.start()

            do {
                activeProductIDs =
                    try await self.features.settingsViewModel
                        .processStoreKitTransactionUpdate(
                            transaction: transaction,
                            signedTransaction: verification.jwsRepresentation,
                            plan: plan
                        )
                await transaction.finish()
                IAPDiagnostics.notice(
                    "event=transaction-update-finished " +
                        "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id))"
                )
            } catch {
                IAPDiagnostics.error(
                    "event=transaction-update-deferred " +
                        "transactionHash=\(IAPDiagnostics.hash(transactionID: transaction.id)) " +
                        "error=\(IAPDiagnostics.safeErrorCode(error))"
                )
            }
        }
    }

    private func configureImageCache() {
        do {
            let settings: ImageCacheSettings = try self.imageCacheConfigurator.configureSharedPipeline()
            self.imageCacheConfigurator.trimConfiguredDataCacheIfNeeded(settings: settings)
            #if DEBUG
            AppDebugLog.write(
                "[BrowseCraftImageCache] configured " +
                "limit=\(settings.displayTitle) " +
                "limitBytes=\(settings.limitBytes) " +
                "trimTargetBytes=\(settings.trimTargetBytes)"
            )
            #endif
        } catch {
            #if DEBUG
            AppDebugLog.write("[BrowseCraftImageCache] configuration failed error=\(error)")
            #endif
        }
    }
}
