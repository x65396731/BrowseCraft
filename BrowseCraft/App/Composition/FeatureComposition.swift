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
    let favoritesFeatureFactory: FavoritesFeatureFactory
    let historyFeatureFactory: HistoryFeatureFactory
    let settingsFeatureFactory: SettingsFeatureFactory
    let settingsViewModel: SettingsViewModel

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
            sourceRuntimeFactory: runtime.sourceRuntimeFactory,
            sourceSelectionStore: sourceSelectionStore,
            systemCookieHeaderProvider: runtime.systemCookieHeaderProvider,
            prepareReaderHistoryRestoreUseCase: PrepareReaderHistoryRestoreUseCase(
                repository: GRDBComicChapterHistoryRepository(database: database)
            )
        )
        self.libraryFeatureFactory = libraryFeatureFactory

        self.sourcesFeatureFactory = SourcesFeatureFactory(
            database: database,
            activeAppUser: account.activeAppUserStore,
            sourceRepository: account.sourceRepository,
            pageContentLoader: runtime.pageLoader,
            pageDataLoader: runtime.pageLoader,
            urlResolver: runtime.urlResolver,
            sourceRuntimeFactory: runtime.sourceRuntimeFactory,
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
            outcomeRefreshRequests: account.ruleGenerationOutcomeRefreshRequests
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
            cloudAssociationAttestationStore: account.cloudAccountPartitionStore,
            cloudSyncCoordinator: account.cloudSyncCoordinator,
            cloudIdentityAssociationCoordinator: account.cloudIdentityAssociationCoordinator,
            storeKitPurchaseIdentityAuthorizer: account.storeKitPurchaseIdentityAuthorizer,
            portalPurchaseEntitlementRefreshCoordinator: account.portalPurchaseEntitlementRefreshCoordinator,
            portalAppleSignInCoordinator: account.portalAppleSignInCoordinator,
            portalSessionCoordinator: account.portalSessionCoordinator,
            pushDeviceRegistrationCoordinator: account.pushDeviceRegistrationCoordinator
        )
        self.settingsFeatureFactory = settingsFeatureFactory
        self.settingsViewModel = settingsFeatureFactory.makeViewModel()
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
            makeRSSDetail: { [libraryFeatureFactory] item, source in
                libraryFeatureFactory.makeRSSContentDetailViewModel(item: item, source: source)
            },
            makeVideoDetail: { [libraryFeatureFactory] item, source in
                libraryFeatureFactory.makeVideoDetailViewModel(item: item, source: source)
            }
        )
    }
}
