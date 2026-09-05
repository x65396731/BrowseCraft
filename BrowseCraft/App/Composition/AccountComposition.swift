import BrowseCraftAPIKit
import BrowseCraftDomain
import CloudKit
import Foundation

/// 中文注释：账户组合体——业务身份、Portal 会话、权益与 CloudKit 同步分区。
/// 这三者互相依赖（同步协调器需要活动用户，身份迁移协调器又需要同步协调器），
/// 拆成三个容器会产生回指，因此按"谁拥有这份数据"归为一组。
/// 受它们直接影响的两个仓储（source/favorite，写入要通知同步）也在这里装配。
@MainActor
final class AccountComposition {
    let activeAppUserStore: ActiveAppUserStore
    let activeAccountScopeStore: ActiveAccountScopeStore
    let cloudAccountSession: CloudAccountSession
    let cloudAccountPartitionStore: GRDBCloudAccountPartitionStore
    let cloudSyncCoordinator: CloudSyncCoordinator
    let cloudIdentityAssociationCoordinator: CloudAppUserIdentityAssociationCoordinator
    let portalSessionCoordinator: PortalSessionCoordinator
    let portalIAPService: any PortalIAPServicing
    let portalPurchaseEntitlementRefreshCoordinator: PortalPurchaseEntitlementRefreshCoordinator
    let portalAppleSignInCoordinator: PortalAppleSignInCoordinator
    let pushDeviceRegistrationCoordinator: PushDeviceRegistrationCoordinator
    let ruleGenerationOutcomeRefreshRequests: RuleGenerationOutcomeRefreshRequests
    let appUserIdentityAdoptionCoordinator: AppUserIdentityAdoptionCoordinator
    let storeKitPurchaseIdentityAuthorizer: StoreKitPurchaseIdentityAuthorizer
    let sourceRepository: SourceRepository
    let favoriteRepository: FavoriteRepository
    /// 中文注释：仅供组合根构造依赖后台 API 的 Feature 客户端；APIKit 不出组合根。
    let portalAPIClient: PortalAPIClient

    init(
        database: AppDatabase,
        activeUserID: UUID,
        cloudKitContainerIdentifier: String
    ) {
        let activeAccountScopeStore: ActiveAccountScopeStore = ActiveAccountScopeStore()
        self.activeAccountScopeStore = activeAccountScopeStore

        let cloudAccountSession: CloudAccountSession = CloudAccountSession(
            stateProvider: CloudKitAccountStateService(
                containerIdentifier: cloudKitContainerIdentifier
            ),
            preferenceStore: UserDefaultsCloudSyncPreferenceStore(),
            activeScopeStore: activeAccountScopeStore
        )
        self.cloudAccountSession = cloudAccountSession

        let activeAppUserStore: ActiveAppUserStore = ActiveAppUserStore(initialUserID: activeUserID)
        self.activeAppUserStore = activeAppUserStore

        let appUserRepository: GRDBAppUserRepository = GRDBAppUserRepository(database: database)
        let appUserIdentityStore: KeychainAppUserIdentityStore = KeychainAppUserIdentityStore()
        let portalIdentityOriginStore: KeychainPortalAppUserIdentityOriginStore =
            KeychainPortalAppUserIdentityOriginStore()
        let cloudKitContainer: CKContainer = CKContainer(identifier: cloudKitContainerIdentifier)

        let portalAPIClient: PortalAPIClient = PortalAPIClient()
        self.portalAPIClient = portalAPIClient

        let portalSessionCoordinator: PortalSessionCoordinator = PortalSessionCoordinator(
            activeAppUser: activeAppUserStore,
            sessionStore: KeychainPortalSessionStore(),
            authenticator: APIKitPortalIdentityAuthenticator(
                api: PortalIdentityAPI(client: portalAPIClient)
            ),
            networkMonitor: NWPathPortalNetworkAvailabilityMonitor(),
            identityOriginStore: portalIdentityOriginStore,
            entitlementCacheResetter: appUserRepository
        )
        self.portalSessionCoordinator = portalSessionCoordinator

        // 中文注释：推送环境跟随 project.yml 的 APS_ENVIRONMENT——Debug 是 development（sandbox），
        // Release / TestFlight 是 production；服务端按设备逐条记录，选错一边就收不到。
        #if DEBUG
        let pushEnvironment: PushEnvironment = .sandbox
        #else
        let pushEnvironment: PushEnvironment = .production
        #endif
        self.pushDeviceRegistrationCoordinator = PushDeviceRegistrationCoordinator(
            environment: pushEnvironment,
            registrar: APIKitPushDeviceClient(
                api: PortalPushAPI(client: portalAPIClient)
            ),
            sessionCoordinator: portalSessionCoordinator
        )
        self.ruleGenerationOutcomeRefreshRequests = RuleGenerationOutcomeRefreshRequests()

        self.cloudIdentityAssociationCoordinator = CloudAppUserIdentityAssociationCoordinator(
            identityStore: CloudKitAppUserIdentityStore(container: cloudKitContainer),
            activeAppUser: activeAppUserStore
        )

        let portalIAPService: APIKitPortalIAPService = APIKitPortalIAPService(
            iapAPI: PortalIAPAPI(client: portalAPIClient)
        )
        self.portalIAPService = portalIAPService
        self.portalPurchaseEntitlementRefreshCoordinator = PortalPurchaseEntitlementRefreshCoordinator(
            activeAppUser: activeAppUserStore,
            portalSessionCoordinator: portalSessionCoordinator,
            portalIAPService: portalIAPService
        )

        let cloudSyncChangeNotifier: CloudSyncChangeNotifier = CloudSyncChangeNotifier()
        let cloudSyncUserContext: CloudSyncUserContext = CloudSyncUserContext()
        let cloudAccountPartitionStore: GRDBCloudAccountPartitionStore = GRDBCloudAccountPartitionStore(
            database: database,
            activeAppUser: activeAppUserStore
        )
        self.cloudAccountPartitionStore = cloudAccountPartitionStore

        self.sourceRepository = GRDBSourceRepository(
            database: database,
            activeAppUser: activeAppUserStore,
            accountScopeProvider: activeAccountScopeStore,
            changeNotifier: cloudSyncChangeNotifier
        )
        self.favoriteRepository = GRDBFavoriteRepository(
            database: database,
            activeAppUser: activeAppUserStore,
            accountScopeProvider: activeAccountScopeStore,
            changeNotifier: cloudSyncChangeNotifier
        )

        let engineStore: GRDBCloudSyncEngineStore = GRDBCloudSyncEngineStore(
            database: database,
            activeAppUser: activeAppUserStore,
            userContext: cloudSyncUserContext
        )
        let cloudRecordStore: CKSyncEngineCloudRecordStore = CKSyncEngineCloudRecordStore(
            container: cloudKitContainer,
            stateStore: engineStore,
            metadataStore: engineStore,
            zoneRecoveryStore: engineStore,
            securityValidator: CloudSyncPayloadSecurityValidator(),
            activeAppUser: activeAppUserStore,
            userContext: cloudSyncUserContext,
            accountScopeProvider: activeAccountScopeStore
        )
        let cloudSyncCoordinator: CloudSyncCoordinator = CloudSyncCoordinator(
            accountSession: cloudAccountSession,
            sourceService: SourceSyncService(
                localStore: GRDBSourceSyncLocalStore(
                    database: database,
                    activeAppUser: activeAppUserStore,
                    userContext: cloudSyncUserContext
                ),
                cloudStore: cloudRecordStore,
                accountScopeProvider: activeAccountScopeStore
            ),
            favoriteItemService: FavoriteItemSyncService(
                localStore: GRDBFavoriteItemSyncLocalStore(
                    database: database,
                    activeAppUser: activeAppUserStore,
                    userContext: cloudSyncUserContext
                ),
                cloudStore: cloudRecordStore,
                activeAppUser: activeAppUserStore,
                userContext: cloudSyncUserContext,
                accountScopeProvider: activeAccountScopeStore
            ),
            cloudStore: cloudRecordStore,
            changeNotifier: cloudSyncChangeNotifier,
            partitionStore: cloudAccountPartitionStore,
            activeAppUser: activeAppUserStore,
            associationAttestationStore: cloudAccountPartitionStore,
            userContext: cloudSyncUserContext,
            retryScheduleProvider: engineStore
        )
        self.cloudSyncCoordinator = cloudSyncCoordinator

        let appUserIdentityAdoptionCoordinator: AppUserIdentityAdoptionCoordinator =
            AppUserIdentityAdoptionCoordinator(
                adoptionStore: GRDBAppUserIdentityAdoptionStore(database: database),
                identityStore: appUserIdentityStore,
                activeAppUser: activeAppUserStore,
                portalSessionCoordinator: portalSessionCoordinator,
                cloudSyncCoordinator: cloudSyncCoordinator
            )
        self.appUserIdentityAdoptionCoordinator = appUserIdentityAdoptionCoordinator

        let portalAppleSignInCoordinator: PortalAppleSignInCoordinator = PortalAppleSignInCoordinator(
            activeAppUser: activeAppUserStore,
            portalSessionCoordinator: portalSessionCoordinator,
            appleAuthorizer: AuthenticationServicesAppleSignInAuthorizer(),
            identityAdoptionCoordinator: appUserIdentityAdoptionCoordinator,
            identityOriginStore: portalIdentityOriginStore
        )
        self.portalAppleSignInCoordinator = portalAppleSignInCoordinator
        self.storeKitPurchaseIdentityAuthorizer = StoreKitPurchaseIdentityAuthorizer(
            activeAppUser: activeAppUserStore,
            portalSessionCoordinator: portalSessionCoordinator,
            appleSignInCoordinator: portalAppleSignInCoordinator
        )
    }

    /// 中文注释：账户相关的启动监听：先接同步引擎，再按用户此前的开关决定是否启动。
    func startCloudAccountMonitoring() async {
        await self.cloudSyncCoordinator.start()
        await self.cloudAccountSession.startIfPreviouslyEnabled()
    }
}
