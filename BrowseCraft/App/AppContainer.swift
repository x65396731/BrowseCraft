import Foundation
import CloudKit
import BrowseCraftAPIKit

/// 中文注释：应用 Composition Root，只持有 App 生命周期共享对象并把 Feature 创建委托给明确 Factory。
final class AppContainer {
    private static let cloudKitContainerIdentifier: String = "iCloud.com.xiefei.AnyPortal"

    private let sourcesFeatureFactory: SourcesFeatureFactory
    private let libraryFeatureFactory: LibraryFeatureFactory
    private let favoritesFeatureFactory: FavoritesFeatureFactory
    private let historyFeatureFactory: HistoryFeatureFactory
    private let settingsFeatureFactory: SettingsFeatureFactory

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
    let portalSessionCoordinator: PortalSessionCoordinator
    let portalIAPService: any PortalIAPServicing
    let portalPurchaseEntitlementRefreshCoordinator:
        PortalPurchaseEntitlementRefreshCoordinator
    let cloudAccountPartitionStore: any CloudAccountPartitioning
    let cloudSyncCoordinator: CloudSyncCoordinator

    init() {
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

        do {
            let database: AppDatabase = try AppDatabase()
            let appUserRepository: GRDBAppUserRepository = GRDBAppUserRepository(database: database)
            let appUserIdentityStore: KeychainAppUserIdentityStore =
                KeychainAppUserIdentityStore()
            let activeUserID: UUID = try AppUserIdentityBootstrapper(
                identityStore: appUserIdentityStore,
                appUserRepository: appUserRepository
            ).bootstrap()
            self.activeAppUserStore = ActiveAppUserStore(initialUserID: activeUserID)
            let cloudKitContainer: CKContainer = CKContainer(
                identifier: Self.cloudKitContainerIdentifier
            )
            let cloudIdentityStore: CloudKitAppUserIdentityStore =
                CloudKitAppUserIdentityStore(container: cloudKitContainer)
            let cloudIdentityAssociationCoordinator:
                CloudAppUserIdentityAssociationCoordinator =
                CloudAppUserIdentityAssociationCoordinator(
                    identityStore: cloudIdentityStore,
                    activeAppUser: self.activeAppUserStore
                )
            self.cloudIdentityAssociationCoordinator = cloudIdentityAssociationCoordinator
            self.storeKitPurchaseIdentityAuthorizer =
                StoreKitPurchaseIdentityAuthorizer(
                    identityStore: cloudIdentityStore,
                    activeAppUser: self.activeAppUserStore
                )
            let portalAPIClient: PortalAPIClient = PortalAPIClient()
            let portalSessionCoordinator: PortalSessionCoordinator =
                PortalSessionCoordinator(
                activeAppUser: self.activeAppUserStore,
                sessionStore: KeychainPortalSessionStore(),
                authenticator: APIKitPortalIdentityAuthenticator(
                    api: PortalIdentityAPI(client: portalAPIClient)
                ),
                networkMonitor: NWPathPortalNetworkAvailabilityMonitor()
            )
            self.portalSessionCoordinator = portalSessionCoordinator
            let portalIAPService: APIKitPortalIAPService = APIKitPortalIAPService(
                identityAPI: PortalIdentityAPI(client: portalAPIClient),
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
            self.appUserIdentityAdoptionCoordinator =
                AppUserIdentityAdoptionCoordinator(
                    adoptionStore: GRDBAppUserIdentityAdoptionStore(
                        database: database
                    ),
                    identityStore: appUserIdentityStore,
                    activeAppUser: self.activeAppUserStore,
                    portalSessionCoordinator: portalSessionCoordinator,
                    cloudSyncCoordinator: cloudSyncCoordinator
                )
            let urlResolver: URLResolvingService = URLResolvingService()
            let sourceCredentialStore: SourceCredentialStoring = InMemorySourceCredentialStore()
            let browserRequestHeaderProvider: any BrowserRequestHeaderProviding = ChromeRequestHeaderProvider()
            let systemCookieHeaderProvider: any SystemCookieHeaderProviding = SharedHTTPCookieHeaderProvider()
            let httpClient: AlamofireHTTPClient = AlamofireHTTPClient(
                credentialProvider: sourceCredentialStore,
                browserRequestHeaderProvider: browserRequestHeaderProvider,
                systemCookieHeaderProvider: systemCookieHeaderProvider,
                managedAPIURLMatcher: PortalAPIConfiguration.isManagedAPIURL
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
                )
            )
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
                sourceSelectionStore: sourceSelectionStore
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
            self.settingsFeatureFactory = SettingsFeatureFactory(
                database: database,
                activeAppUser: self.activeAppUserStore,
                imageCacheConfigurator: imageCacheConfigurator,
                cloudAccountSession: cloudAccountSession,
                cloudAccountPartitionStore: cloudAccountPartitionStore,
                cloudAssociationAttestationStore:
                    cloudAccountPartitionStore,
                cloudSyncCoordinator: cloudSyncCoordinator,
                cloudIdentityAssociationCoordinator: cloudIdentityAssociationCoordinator,
                storeKitPurchaseIdentityAuthorizer:
                    self.storeKitPurchaseIdentityAuthorizer,
                portalPurchaseEntitlementRefreshCoordinator:
                    self.portalPurchaseEntitlementRefreshCoordinator,
                appUserIdentityAdoptionCoordinator:
                    self.appUserIdentityAdoptionCoordinator
            )
            self.browserRequestHeaderProvider = browserRequestHeaderProvider
            self.systemCookieHeaderProvider = systemCookieHeaderProvider
        } catch {
            fatalError("Failed to build AppContainer: \(error)")
        }

        self.configureImageCache()
    }

    func startApplicationServices() async {
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
        return self.settingsFeatureFactory.makeViewModel()
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

    private func configureImageCache() {
        do {
            let settings: ImageCacheSettings = try self.imageCacheConfigurator.configureSharedPipeline()
            self.imageCacheConfigurator.trimConfiguredDataCacheIfNeeded(settings: settings)
            #if DEBUG
            print(
                "[BrowseCraftImageCache] configured " +
                "limit=\(settings.displayTitle) " +
                "limitBytes=\(settings.limitBytes) " +
                "trimTargetBytes=\(settings.trimTargetBytes)"
            )
            #endif
        } catch {
            #if DEBUG
            print("[BrowseCraftImageCache] configuration failed error=\(error)")
            #endif
        }
    }
}
