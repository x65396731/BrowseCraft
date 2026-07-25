struct SettingsFeatureFactory {
    private let database: AppDatabase
    private let activeAppUser: any ActiveAppUserProviding
    private let imageCacheConfigurator: ImageCacheConfigurator
    private let cloudAccountSession: CloudAccountSession
    private let cloudAccountPartitionStore: any CloudAccountPartitioning
    private let cloudAssociationAttestationStore:
        any CloudAppUserAssociationAttestationStoring
    private let cloudSyncCoordinator: CloudSyncCoordinator
    private let cloudIdentityAssociationCoordinator:
        CloudAppUserIdentityAssociationCoordinator
    private let storeKitPurchaseIdentityAuthorizer:
        StoreKitPurchaseIdentityAuthorizer
    private let portalPurchaseEntitlementRefreshCoordinator:
        PortalPurchaseEntitlementRefreshCoordinator
    private let appUserIdentityAdoptionCoordinator:
        AppUserIdentityAdoptionCoordinator

    init(
        database: AppDatabase,
        activeAppUser: any ActiveAppUserProviding,
        imageCacheConfigurator: ImageCacheConfigurator,
        cloudAccountSession: CloudAccountSession,
        cloudAccountPartitionStore: any CloudAccountPartitioning,
        cloudAssociationAttestationStore:
            any CloudAppUserAssociationAttestationStoring,
        cloudSyncCoordinator: CloudSyncCoordinator,
        cloudIdentityAssociationCoordinator: CloudAppUserIdentityAssociationCoordinator,
        storeKitPurchaseIdentityAuthorizer: StoreKitPurchaseIdentityAuthorizer,
        portalPurchaseEntitlementRefreshCoordinator:
            PortalPurchaseEntitlementRefreshCoordinator,
        appUserIdentityAdoptionCoordinator: AppUserIdentityAdoptionCoordinator
    ) {
        self.database = database
        self.activeAppUser = activeAppUser
        self.imageCacheConfigurator = imageCacheConfigurator
        self.cloudAccountSession = cloudAccountSession
        self.cloudAccountPartitionStore = cloudAccountPartitionStore
        self.cloudAssociationAttestationStore =
            cloudAssociationAttestationStore
        self.cloudSyncCoordinator = cloudSyncCoordinator
        self.cloudIdentityAssociationCoordinator = cloudIdentityAssociationCoordinator
        self.storeKitPurchaseIdentityAuthorizer =
            storeKitPurchaseIdentityAuthorizer
        self.portalPurchaseEntitlementRefreshCoordinator =
            portalPurchaseEntitlementRefreshCoordinator
        self.appUserIdentityAdoptionCoordinator = appUserIdentityAdoptionCoordinator
    }

    func makeViewModel() -> SettingsViewModel {
        return SettingsViewModel(
            imageCacheConfigurator: self.imageCacheConfigurator,
            appUserRepository: GRDBAppUserRepository(database: self.database),
            activeAppUser: self.activeAppUser,
            purchaseIdentityAuthorizer: self.storeKitPurchaseIdentityAuthorizer,
            portalPurchaseEntitlementRefreshCoordinator:
                self.portalPurchaseEntitlementRefreshCoordinator
        )
    }

    @MainActor
    func makeCloudSyncViewModel() -> CloudSyncSettingsViewModel {
        return CloudSyncSettingsViewModel(
            accountSession: self.cloudAccountSession,
            partitionStore: self.cloudAccountPartitionStore,
            coordinator: self.cloudSyncCoordinator,
            identityAssociationCoordinator: self.cloudIdentityAssociationCoordinator,
            identityAdoptionCoordinator: self.appUserIdentityAdoptionCoordinator,
            associationAttestationStore:
                self.cloudAssociationAttestationStore,
            activeAppUser: self.activeAppUser
        )
    }
}
