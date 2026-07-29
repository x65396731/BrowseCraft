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
    private let portalAppleSignInCoordinator: PortalAppleSignInCoordinator
    private let portalSessionCoordinator: PortalSessionCoordinator

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
        portalAppleSignInCoordinator: PortalAppleSignInCoordinator,
        portalSessionCoordinator: PortalSessionCoordinator
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
        self.portalAppleSignInCoordinator = portalAppleSignInCoordinator
        self.portalSessionCoordinator = portalSessionCoordinator
    }

    @MainActor
    func makeViewModel() -> SettingsViewModel {
        return SettingsViewModel(
            imageCacheConfigurator: self.imageCacheConfigurator,
            purchaseCoordinator: PortalPurchaseCoordinator(
                appUserRepository: GRDBAppUserRepository(database: self.database),
                activeAppUser: self.activeAppUser,
                identityAuthorizer: self.storeKitPurchaseIdentityAuthorizer,
                entitlementRefreshCoordinator: self.portalPurchaseEntitlementRefreshCoordinator,
                supportedProductIDs: Set(InAppPurchasePlan.activePlans.map(\.productID))
            ),
            portalSignInAction: {
                return try await self.portalAppleSignInCoordinator.signIn()
            },
            portalSignOutAction: {
                try await self.portalSessionCoordinator.logout()
            },
            portalSessionSnapshotAction: {
                return await self.portalSessionCoordinator.snapshot()
            }
        )
    }

    @MainActor
    func makeCloudSyncViewModel() -> CloudSyncSettingsViewModel {
        return CloudSyncSettingsViewModel(
            accountSession: self.cloudAccountSession,
            partitionStore: self.cloudAccountPartitionStore,
            coordinator: self.cloudSyncCoordinator,
            identityAssociationCoordinator: self.cloudIdentityAssociationCoordinator,
            associationAttestationStore:
                self.cloudAssociationAttestationStore,
            activeAppUser: self.activeAppUser
        )
    }
}
