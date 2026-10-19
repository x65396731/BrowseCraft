import BrowseCraftAPIKit
import BrowseCraftDomain
import Foundation

/// 中文注释：Feature 组合体——把账户与运行时组合体的产物接进各页面工厂。
/// 这里是唯一知道"哪个页面需要什么"的地方；页面工厂本身只见端口与用例。
@MainActor
final class FeatureComposition {
    let sourceSelectionStore: SourceSelectionStore
    let sourcesFeatureFactory: SourcesFeatureFactory
    let libraryFeatureFactory: LibraryFeatureFactory
    let bookFeatureFactory: BookFeatureFactory
    let favoritesFeatureFactory: FavoritesFeatureFactory
    let historyFeatureFactory: HistoryFeatureFactory
    let settingsFeatureFactory: SettingsFeatureFactory
    let settingsViewModel: SettingsViewModel
    /// 页内问题报告的发送用例（Problem-Report-Design.md 第七节），根视图注入环境，库页与三种详情页的面板取用。
    let problemReportUseCase: SubmitProblemReportUseCase

    init(
        database: AppDatabase,
        account: AccountComposition,
        runtime: SourceRuntimeComposition,
        imageCacheConfigurator: ImageCacheConfigurator
    ) {
        let sourceSelectionStore: SourceSelectionStore = SourceSelectionStore()
        self.sourceSelectionStore = sourceSelectionStore

        let libraryFeatureFactory: LibraryFeatureFactory = LibraryFeatureFactory(
            database: database,
            activeAppUser: account.activeAppUserStore,
            sourceRepository: account.sourceRepository,
            favoriteRepository: account.favoriteRepository,
            sourceCredentialStore: runtime.sourceCredentialStore,
            protectedResourceLoader: runtime.protectedResourceLoader,
            sourceRuntimeResolver: runtime.sourceRuntimeResolver,
            sourceSelectionStore: sourceSelectionStore,
            systemCookieHeaderProvider: runtime.systemCookieHeaderProvider,
            prepareReaderHistoryRestoreUseCase: PrepareReaderHistoryRestoreUseCase(
                repository: GRDBComicChapterHistoryRepository(database: database)
            )
        )
        self.libraryFeatureFactory = libraryFeatureFactory
        self.bookFeatureFactory = BookFeatureFactory(
            database: database,
            activeAppUser: account.activeAppUserStore,
            runtimeResolver: runtime.sourceRuntimeResolver,
            favoriteRepository: account.favoriteRepository,
            sourceCredentialStore: runtime.sourceCredentialStore
        )

        self.sourcesFeatureFactory = SourcesFeatureFactory(
            database: database,
            activeAppUser: account.activeAppUserStore,
            sourceRepository: account.sourceRepository,
            pageDataLoader: runtime.pageLoader,
            sourceRuntimeResolver: runtime.sourceRuntimeResolver,
            sourceSelectionStore: sourceSelectionStore,
            // 中文注释：APIKit 只在组合根出现；Feature 工厂只见 Application 端口（架构边界脚本）。
            videoGenerationTaskClient: APIKitVideoGenerationTaskClient(
                api: PortalRuleGenerationAPI(client: account.portalAPIClient)
            ),
            portalAccessTokenProvider: account.portalSessionCoordinator,
            pushNotificationAuthorizer: UserNotificationsPushAuthorizationService(),
            videoGenerationOutcomesClient: APIKitVideoGenerationOutcomesClient(
                api: PortalRuleGenerationAPI(client: account.portalAPIClient)
            ),
            generationRatesClient: APIKitGenerationRatesClient(
                api: PortalGenerationRatesAPI(client: account.portalAPIClient)
            ),
            coinWalletStore: account.coinWalletStore
        )

        self.favoritesFeatureFactory = FavoritesFeatureFactory(
            sourceRepository: account.sourceRepository,
            favoriteRepository: account.favoriteRepository
        )

        self.historyFeatureFactory = HistoryFeatureFactory(
            database: database,
            activeAppUser: account.activeAppUserStore,
            sourceRepository: account.sourceRepository,
            videoPlayerViewModelFactory: { history, source in
                libraryFeatureFactory.makeVideoPlayerViewModel(history: history, source: source)
            }
        )

        let settingsFeatureFactory: SettingsFeatureFactory = SettingsFeatureFactory(
            database: database,
            activeAppUser: account.activeAppUserStore,
            imageCacheConfigurator: imageCacheConfigurator,
            cloudAccountSession: account.cloudAccountSession,
            cloudAccountPartitionStore: account.cloudAccountPartitionStore,
            historyEntrySyncLocalStore: account.historyEntrySyncLocalStore,
            cloudAssociationAttestationStore: account.cloudAccountPartitionStore,
            cloudSyncCoordinator: account.cloudSyncCoordinator,
            cloudIdentityAssociationCoordinator: account.cloudIdentityAssociationCoordinator,
            storeKitPurchaseIdentityAuthorizer: account.storeKitPurchaseIdentityAuthorizer,
            portalPurchaseEntitlementRefreshCoordinator: account.portalPurchaseEntitlementRefreshCoordinator,
            portalAppleSignInCoordinator: account.portalAppleSignInCoordinator,
            portalSessionCoordinator: account.portalSessionCoordinator,
            pushDeviceRegistrationCoordinator: account.pushDeviceRegistrationCoordinator,
            pushNotificationAuthorizer: UserNotificationsPushAuthorizationService(),
            coinWalletStore: account.coinWalletStore,
            accountDeletionCoordinator: account.accountDeletionCoordinator
        )
        self.settingsFeatureFactory = settingsFeatureFactory
        self.settingsViewModel = settingsFeatureFactory.makeViewModel()
        self.problemReportUseCase = SubmitProblemReportUseCase(
            submitter: APIKitProblemReportClient(
                api: PortalProblemReportAPI(client: account.portalAPIClient)
            ),
            logProvider: AppLoggingProblemReportLogProvider(),
            sourceRepository: account.sourceRepository,
            accessTokenProvider: account.portalSessionCoordinator,
            environment: {
                let identity: DiagnosticIdentity = DiagnosticIdentityStore.shared.identity
                return ProblemReportEnvironment(
                    appVersion: DiagnosticDeviceInfo.appVersion,
                    buildNumber: DiagnosticDeviceInfo.buildNumber,
                    systemVersion: DiagnosticDeviceInfo.systemVersion,
                    deviceModel: DiagnosticDeviceInfo.deviceModel,
                    locale: DiagnosticDeviceInfo.interfaceLanguage,
                    diagnosticCode: identity.diagnosticCode,
                    sessionID: identity.sessionId
                )
            }
        )
    }

    func makeLibraryContentViewModelFactory() -> LibraryContentViewModelFactory {
        return LibraryContentViewModelFactory(
            makeComicDetail: { [libraryFeatureFactory] item, source in
                libraryFeatureFactory.makeComicDetailViewModel(item: item, source: source)
            },
            makeReader: { [libraryFeatureFactory] item, source, chapter in
                libraryFeatureFactory.makeReaderViewModel(
                    item: item,
                    source: source,
                    selectedChapter: chapter
                )
            },
            makeHistoryReader: { [libraryFeatureFactory] history, source in
                libraryFeatureFactory.makeReaderViewModel(history: history, source: source)
            },
            makeVideoDetail: { [libraryFeatureFactory] item, source in
                libraryFeatureFactory.makeVideoDetailViewModel(item: item, source: source)
            },
            makeBookSiteDetail: { [bookFeatureFactory] item, source in
                bookFeatureFactory.makeSiteDetailViewModel(item: item, source: source)
            },
            makeBookSiteReader: { [bookFeatureFactory] selection in
                bookFeatureFactory.makeSiteReaderViewModel(selection: selection)
            }
        )
    }
}
