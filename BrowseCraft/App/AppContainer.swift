import Foundation
import CloudKit
import BrowseCraftAPIKit
import StoreKit

/// 中文注释：应用 Composition Root，只持有 App 生命周期共享对象并把 Feature 创建委托给明确 Factory。
@MainActor
final class AppContainer {
    private static let cloudKitContainerIdentifier: String = "iCloud.com.xiefei.AnyPortal"

    private let sourcesFeatureFactory: SourcesFeatureFactory
    private let libraryFeatureFactory: LibraryFeatureFactory
    private let favoritesFeatureFactory: FavoritesFeatureFactory
    private let historyFeatureFactory: HistoryFeatureFactory
    private let settingsFeatureFactory: SettingsFeatureFactory
    private let settingsViewModel: SettingsViewModel
    private var storeKitTransactionUpdatesTask: Task<Void, Never>?
    #if DEBUG
    /// 中文注释：显式 runtime audit 入口（BC-EVIDENCE-076.2）；无 launch environment 时完全惰性。
    private let videoRuntimeAuditLauncher: VideoRuntimeAuditLauncher
    /// 中文注释：BC-EVIDENCE-077.1——audit 的前台 WebUI 承载者，由根视图覆盖层观察；无 audit 时空闲。
    let videoRuntimeAuditWebUIPresenter: VideoRuntimeAuditWebUIPresenter
    #endif

    let browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    let systemCookieHeaderProvider: any SystemCookieHeaderProviding
    /// 中文注释：缓存配置器与 App 生命周期一致，供启动配置和 Settings 共用。
    let imageCacheConfigurator: ImageCacheConfigurator
    /// 中文注释：账户 Session 先于真实同步引擎接线，统一提供活动数据空间和账户切换世代。
    let cloudAccountSession: CloudAccountSession
    let activeAccountScopeStore: ActiveAccountScopeStore
    /// 中文注释：业务 AppUser 与 CloudKit 同步分区独立，后续认证和权益共用此稳定 UUID。
    let activeAppUserStore: ActiveAppUserStore
    let cloudIdentityAssociationCoordinator: CloudAppUserIdentityAssociationCoordinator
    let storeKitPurchaseIdentityAuthorizer: StoreKitPurchaseIdentityAuthorizer
    let appUserIdentityAdoptionCoordinator: AppUserIdentityAdoptionCoordinator
    let portalAppleSignInCoordinator: PortalAppleSignInCoordinator
    let portalSessionCoordinator: PortalSessionCoordinator
    let portalIAPService: any PortalIAPServicing
    let portalPurchaseEntitlementRefreshCoordinator:
        PortalPurchaseEntitlementRefreshCoordinator
    let cloudAccountPartitionStore: any CloudAccountPartitioning
    let cloudSyncCoordinator: CloudSyncCoordinator

    init(bootstrap: AppBootstrapDependencies) throws {
        let imageCacheConfigurator: ImageCacheConfigurator = ImageCacheConfigurator()
        let activeAccountScopeStore: ActiveAccountScopeStore = ActiveAccountScopeStore()
        self.imageCacheConfigurator = imageCacheConfigurator
        self.activeAccountScopeStore = activeAccountScopeStore
        let cloudAccountSession: CloudAccountSession = CloudAccountSession(
            stateProvider: CloudKitAccountStateService(
                containerIdentifier: Self.cloudKitContainerIdentifier
            ),
            preferenceStore: UserDefaultsCloudSyncPreferenceStore(),
            activeScopeStore: activeAccountScopeStore
        )
        self.cloudAccountSession = cloudAccountSession

        let database: AppDatabase = bootstrap.database
            let appUserRepository: GRDBAppUserRepository = GRDBAppUserRepository(database: database)
            let appUserIdentityStore: KeychainAppUserIdentityStore =
                KeychainAppUserIdentityStore()
            let portalIdentityOriginStore:
                KeychainPortalAppUserIdentityOriginStore =
                KeychainPortalAppUserIdentityOriginStore()
            let activeUserID: UUID = bootstrap.activeUserID
            self.activeAppUserStore = ActiveAppUserStore(initialUserID: activeUserID)
            let cloudKitContainer: CKContainer = CKContainer(
                identifier: Self.cloudKitContainerIdentifier
            )
            let cloudIdentityStore: CloudKitAppUserIdentityStore =
                CloudKitAppUserIdentityStore(container: cloudKitContainer)
            let portalAPIClient: PortalAPIClient = PortalAPIClient()
            let portalSessionCoordinator: PortalSessionCoordinator =
                PortalSessionCoordinator(
                    activeAppUser: self.activeAppUserStore,
                    sessionStore: KeychainPortalSessionStore(),
                    authenticator: APIKitPortalIdentityAuthenticator(
                        api: PortalIdentityAPI(client: portalAPIClient)
                    ),
                    networkMonitor: NWPathPortalNetworkAvailabilityMonitor(),
                    identityOriginStore: portalIdentityOriginStore,
                    entitlementCacheResetter: appUserRepository
                )
            self.portalSessionCoordinator = portalSessionCoordinator
            let cloudIdentityAssociationCoordinator:
                CloudAppUserIdentityAssociationCoordinator =
                CloudAppUserIdentityAssociationCoordinator(
                    identityStore: cloudIdentityStore,
                    activeAppUser: self.activeAppUserStore
                )
            self.cloudIdentityAssociationCoordinator = cloudIdentityAssociationCoordinator
            let portalIAPService: APIKitPortalIAPService = APIKitPortalIAPService(
                iapAPI: PortalIAPAPI(client: portalAPIClient)
            )
            self.portalIAPService = portalIAPService
            self.portalPurchaseEntitlementRefreshCoordinator =
                PortalPurchaseEntitlementRefreshCoordinator(
                    activeAppUser: self.activeAppUserStore,
                    portalSessionCoordinator: portalSessionCoordinator,
                    portalIAPService: portalIAPService
                )
            let cloudSyncChangeNotifier: CloudSyncChangeNotifier = CloudSyncChangeNotifier()
            let cloudSyncUserContext: CloudSyncUserContext =
                CloudSyncUserContext()
            let cloudAccountPartitionStore: GRDBCloudAccountPartitionStore =
                GRDBCloudAccountPartitionStore(
                    database: database,
                    activeAppUser: self.activeAppUserStore
                )
            self.cloudAccountPartitionStore = cloudAccountPartitionStore
            let sourceRepository: SourceRepository = GRDBSourceRepository(
                database: database,
                activeAppUser: self.activeAppUserStore,
                accountScopeProvider: activeAccountScopeStore,
                changeNotifier: cloudSyncChangeNotifier
            )
            let favoriteRepository: FavoriteRepository = GRDBFavoriteRepository(
                database: database,
                activeAppUser: self.activeAppUserStore,
                accountScopeProvider: activeAccountScopeStore,
                changeNotifier: cloudSyncChangeNotifier
            )
            let engineStore: GRDBCloudSyncEngineStore = GRDBCloudSyncEngineStore(
                database: database,
                activeAppUser: self.activeAppUserStore,
                userContext: cloudSyncUserContext
            )
            let cloudRecordStore: CKSyncEngineCloudRecordStore = CKSyncEngineCloudRecordStore(
                container: cloudKitContainer,
                stateStore: engineStore,
                metadataStore: engineStore,
                zoneRecoveryStore: engineStore,
                securityValidator: CloudSyncPayloadSecurityValidator(),
                activeAppUser: self.activeAppUserStore,
                userContext: cloudSyncUserContext,
                accountScopeProvider: activeAccountScopeStore
            )
            let cloudSyncCoordinator: CloudSyncCoordinator = CloudSyncCoordinator(
                accountSession: cloudAccountSession,
                sourceService: SourceSyncService(
                    localStore: GRDBSourceSyncLocalStore(
                        database: database,
                        activeAppUser: self.activeAppUserStore,
                        userContext: cloudSyncUserContext
                    ),
                    cloudStore: cloudRecordStore,
                    accountScopeProvider: activeAccountScopeStore
                ),
                favoriteItemService: FavoriteItemSyncService(
                    localStore: GRDBFavoriteItemSyncLocalStore(
                        database: database,
                        activeAppUser: self.activeAppUserStore,
                        userContext: cloudSyncUserContext
                    ),
                    cloudStore: cloudRecordStore,
                    activeAppUser: self.activeAppUserStore,
                    userContext: cloudSyncUserContext,
                    accountScopeProvider: activeAccountScopeStore
                ),
                cloudStore: cloudRecordStore,
                changeNotifier: cloudSyncChangeNotifier,
                partitionStore: cloudAccountPartitionStore,
                activeAppUser: self.activeAppUserStore,
                associationAttestationStore: cloudAccountPartitionStore,
                userContext: cloudSyncUserContext,
                retryScheduleProvider: engineStore
            )
            self.cloudSyncCoordinator = cloudSyncCoordinator
            let appUserIdentityAdoptionCoordinator:
                AppUserIdentityAdoptionCoordinator =
                AppUserIdentityAdoptionCoordinator(
                    adoptionStore: GRDBAppUserIdentityAdoptionStore(
                        database: database
                    ),
                    identityStore: appUserIdentityStore,
                    activeAppUser: self.activeAppUserStore,
                    portalSessionCoordinator: portalSessionCoordinator,
                    cloudSyncCoordinator: cloudSyncCoordinator
                )
            self.appUserIdentityAdoptionCoordinator =
                appUserIdentityAdoptionCoordinator
            let portalAppleSignInCoordinator: PortalAppleSignInCoordinator =
                PortalAppleSignInCoordinator(
                    activeAppUser: self.activeAppUserStore,
                    portalSessionCoordinator: portalSessionCoordinator,
                    appleAuthorizer:
                        AuthenticationServicesAppleSignInAuthorizer(),
                    identityAdoptionCoordinator:
                        appUserIdentityAdoptionCoordinator,
                    identityOriginStore: portalIdentityOriginStore
                )
            self.portalAppleSignInCoordinator = portalAppleSignInCoordinator
            self.storeKitPurchaseIdentityAuthorizer =
                StoreKitPurchaseIdentityAuthorizer(
                    activeAppUser: self.activeAppUserStore,
                    portalSessionCoordinator: portalSessionCoordinator,
                    appleSignInCoordinator: portalAppleSignInCoordinator
                )
            let urlResolver: URLResolvingService = URLResolvingService()
            let sourceCredentialStore: SourceCredentialStoring = InMemorySourceCredentialStore()
            let browserRequestHeaderProvider: any BrowserRequestHeaderProviding = ChromeRequestHeaderProvider()
            let systemCookieHeaderProvider: any SystemCookieHeaderProviding = SharedHTTPCookieHeaderProvider()
            let httpClient: AlamofireHTTPClient = AlamofireHTTPClient(
                credentialProvider: sourceCredentialStore,
                browserRequestHeaderProvider: browserRequestHeaderProvider,
                systemCookieHeaderProvider: systemCookieHeaderProvider,
                managedAPIURLMatcher: { url in PortalAPIConfiguration.isManagedAPIURL(url) }
            )
            let pageLoader: DefaultPageLoader = DefaultPageLoader(
                httpContentLoader: httpClient,
                httpDataLoader: httpClient,
                credentialProvider: sourceCredentialStore,
                browserRequestHeaderProvider: browserRequestHeaderProvider,
                systemCookieHeaderProvider: systemCookieHeaderProvider
            )
            let comicRuleParser: ComicRuleSourceParsingService = CoreComicRuleSourceParser()
            let sourceRuntimeFactory: SourceRuntimeFactory = SourceRuntimeFactory(
                comicSourceRuntimeFactory: ComicSourceRuntimeFactory(
                    pageContentLoader: pageLoader,
                    comicRuleParser: comicRuleParser,
                    urlResolver: urlResolver,
                    defaultUserAgent: browserRequestHeaderProvider.userAgent
                ),
                rssSourceRuntimeFactory: RSSSourceRuntimeFactory(
                    pageContentLoader: pageLoader,
                    pageDataLoader: pageLoader
                ),
                videoSourceRuntimeFactory: VideoSourceRuntimeFactory(
                    pageContentLoader: pageLoader,
                    parser: CoreVideoRuleSourceParser(),
                    credentialProvider: sourceCredentialStore
                ),
                validateSourceAccess: { source in
                    guard source.isBuiltIn == false else {
                        return
                    }
                    let reconciledSources: [Source] =
                        try sourceRepository.reconcileSourceSlotAssignments()
                    if let persistedSource: Source =
                        reconciledSources.first(where: { candidate in
                            return candidate.id == source.id
                        }) {
                        guard persistedSource.accessState == .active else {
                            throw SourceRepositoryError.sourceLockedBySlotLimit
                        }
                        return
                    }
                    guard source.accessState == .active else {
                        throw SourceRepositoryError.sourceLockedBySlotLimit
                    }
                }
            )
            #if DEBUG
            // 中文注释：audit launcher 与正常视频链共用同一 pageLoader/parser/credential 组件，
            // 不建第二套装配（BC-EVIDENCE-076.1）。
            let videoRuntimeAuditWebUIPresenter: VideoRuntimeAuditWebUIPresenter =
                VideoRuntimeAuditWebUIPresenter()
            self.videoRuntimeAuditWebUIPresenter = videoRuntimeAuditWebUIPresenter
            self.videoRuntimeAuditLauncher = VideoRuntimeAuditLauncher(
                runtimeFactory: VideoSourceRuntimeFactory(
                    pageContentLoader: pageLoader,
                    parser: CoreVideoRuleSourceParser(),
                    credentialProvider: sourceCredentialStore
                ),
                webUIObserver: videoRuntimeAuditWebUIPresenter,
                browserRequestHeaderProvider: browserRequestHeaderProvider
            )
            #endif
            let protectedResourceLoader: ReaderProtectedResourceLoader = ReaderProtectedResourceLoader(
                legacyLoader: ProtectedResourceLoader(
                    dataLoader: pageLoader,
                    decryptor: CommonCryptoProtectedResourceDecryptor(),
                    defaultUserAgent: browserRequestHeaderProvider.userAgent
                ),
                pipelineExecutor: ResourcePipelineExecutor(
                    dataLoader: pageLoader,
                    cryptography: CommonCryptoResourcePipelineCryptography()
                )
            )
            let sourceSelectionStore: SourceSelectionStore = SourceSelectionStore()
            let libraryFeatureFactory: LibraryFeatureFactory = LibraryFeatureFactory(
                database: database,
                activeAppUser: self.activeAppUserStore,
                sourceRepository: sourceRepository,
                favoriteRepository: favoriteRepository,
                sourceCredentialStore: sourceCredentialStore,
                protectedResourceLoader: protectedResourceLoader,
                sourceRuntimeFactory: sourceRuntimeFactory,
                sourceSelectionStore: sourceSelectionStore,
                systemCookieHeaderProvider: systemCookieHeaderProvider,
                prepareReaderHistoryRestoreUseCase: PrepareReaderHistoryRestoreUseCase(
                    repository: GRDBComicChapterHistoryRepository(database: database)
                )
            )

            self.sourcesFeatureFactory = SourcesFeatureFactory(
                database: database,
                activeAppUser: self.activeAppUserStore,
                sourceRepository: sourceRepository,
                pageContentLoader: pageLoader,
                pageDataLoader: pageLoader,
                urlResolver: urlResolver,
                sourceRuntimeFactory: sourceRuntimeFactory,
                sourceSelectionStore: sourceSelectionStore,
                // 中文注释：APIKit 只在组合根出现；Feature 工厂只见 Application 端口（架构边界脚本）。
                videoGenerationTaskClient: APIKitVideoGenerationTaskClient(
                    api: PortalRuleGenerationAPI(client: portalAPIClient)
                ),
                portalAccessTokenProvider: portalSessionCoordinator
            )
            self.libraryFeatureFactory = libraryFeatureFactory
            self.favoritesFeatureFactory = FavoritesFeatureFactory(
                sourceRepository: sourceRepository,
                favoriteRepository: favoriteRepository
            )
            self.historyFeatureFactory = HistoryFeatureFactory(
                database: database,
                activeAppUser: self.activeAppUserStore,
                sourceRepository: sourceRepository,
                videoPlayerViewModelFactory: { history, source in
                    libraryFeatureFactory.makeVideoPlayerViewModel(history: history, source: source)
                }
            )
            let settingsFeatureFactory: SettingsFeatureFactory =
                SettingsFeatureFactory(
                    database: database,
                    activeAppUser: self.activeAppUserStore,
                    imageCacheConfigurator: imageCacheConfigurator,
                    cloudAccountSession: cloudAccountSession,
                    cloudAccountPartitionStore: cloudAccountPartitionStore,
                    cloudAssociationAttestationStore:
                        cloudAccountPartitionStore,
                    cloudSyncCoordinator: cloudSyncCoordinator,
                    cloudIdentityAssociationCoordinator:
                        cloudIdentityAssociationCoordinator,
                    storeKitPurchaseIdentityAuthorizer:
                        self.storeKitPurchaseIdentityAuthorizer,
                    portalPurchaseEntitlementRefreshCoordinator:
                        self.portalPurchaseEntitlementRefreshCoordinator,
                    portalAppleSignInCoordinator:
                        self.portalAppleSignInCoordinator,
                    portalSessionCoordinator: portalSessionCoordinator
                )
            self.settingsFeatureFactory = settingsFeatureFactory
            self.settingsViewModel = settingsFeatureFactory.makeViewModel()
            self.browserRequestHeaderProvider = browserRequestHeaderProvider
            self.systemCookieHeaderProvider = systemCookieHeaderProvider

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
        async let portalSession: Void = self.portalSessionCoordinator.start()
        async let cloudAccount: Void = self.startCloudAccountMonitoring()
        _ = await (portalSession, cloudAccount)
    }

    func handleAppBecameActive() async {
        async let portalSession: Void = self.portalSessionCoordinator.handleAppBecameActive()
        async let cloudSync: Void = self.cloudSyncCoordinator.requestSync(trigger: .foreground)
        _ = await (portalSession, cloudSync)
    }

    func handleCloudRemoteNotification() async throws -> CloudSyncRunResult {
        return try await self.cloudSyncCoordinator.synchronize(trigger: .remoteNotification)
    }

    func makeSourcesViewModel() -> SourcesViewModel {
        return self.sourcesFeatureFactory.makeViewModel()
    }

    func makeLibraryViewModel() -> LibraryViewModel {
        return self.libraryFeatureFactory.makeViewModel()
    }

    func makeFavoritesViewModel() -> FavoritesViewModel {
        return self.favoritesFeatureFactory.makeViewModel()
    }

    func makeHistoryViewModel() -> HistoryViewModel {
        return self.historyFeatureFactory.makeViewModel()
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        return self.settingsViewModel
    }

    @MainActor
    func makeCloudSyncSettingsViewModel() -> CloudSyncSettingsViewModel {
        return self.settingsFeatureFactory.makeCloudSyncViewModel()
    }

    func makeLibraryContentViewModelFactory() -> LibraryContentViewModelFactory {
        return LibraryContentViewModelFactory(
            makeComicDetail: { item, source in
                self.libraryFeatureFactory.makeComicDetailViewModel(item: item, source: source)
            },
            makeReader: { item, source, chapter in
                self.libraryFeatureFactory.makeReaderViewModel(
                    item: item,
                    source: source,
                    selectedChapter: chapter
                )
            },
            makeHistoryReader: { history, source in
                self.libraryFeatureFactory.makeReaderViewModel(history: history, source: source)
            },
            makeRSSDetail: { item, source in
                self.libraryFeatureFactory.makeRSSContentDetailViewModel(item: item, source: source)
            },
            makeVideoDetail: { item, source in
                self.libraryFeatureFactory.makeVideoDetailViewModel(item: item, source: source)
            }
        )
    }

    private func startCloudAccountMonitoring() async {
        await self.cloudSyncCoordinator.start()
        await self.cloudAccountSession.startIfPreviouslyEnabled()
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
            self.settingsViewModel.recordStoreKitTransactionUpdate(
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
            await self.portalSessionCoordinator.start()

            do {
                activeProductIDs =
                    try await self.settingsViewModel
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
