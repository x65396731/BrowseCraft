import Foundation

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
    private let pushDeviceRegistrationCoordinator: PushDeviceRegistrationCoordinator

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
        portalSessionCoordinator: PortalSessionCoordinator,
        pushDeviceRegistrationCoordinator: PushDeviceRegistrationCoordinator
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
        self.pushDeviceRegistrationCoordinator = pushDeviceRegistrationCoordinator
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
                let userID: UUID = try await self.portalAppleSignInCoordinator.signIn()
                // 中文注释：登录成功后把已缓存的 device token 挂到新用户名下。
                await self.pushDeviceRegistrationCoordinator.synchronizeRegistration()
                return userID
            },
            portalSignOutAction: {
                // 中文注释：必须在 logout 之前——注销设备要用还没被撤销的 access token。
                await self.pushDeviceRegistrationCoordinator.unregisterCurrentDevice()
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
