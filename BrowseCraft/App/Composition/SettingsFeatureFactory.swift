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
    private let coinWalletStore: CoinWalletStore

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
        pushDeviceRegistrationCoordinator: PushDeviceRegistrationCoordinator,
        coinWalletStore: CoinWalletStore
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
        self.coinWalletStore = coinWalletStore
    }

    @MainActor
    func makeViewModel() -> SettingsViewModel {
        return SettingsViewModel(
            imageCacheManager: self.imageCacheConfigurator,
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
                // 设计书 30.6：登录即拉一次余额（新账户此时已有赠送）。
                await self.coinWalletStore.refresh()
                return userID
            },
            portalSignOutAction: {
                // 中文注释：必须在 logout 之前——注销设备要用还没被撤销的 access token。
                await self.pushDeviceRegistrationCoordinator.unregisterCurrentDevice()
                try await self.portalSessionCoordinator.logout()
                // 设计书 30.6：登出清掉本地余额缓存，不迁移、不合并。
                self.coinWalletStore.markSignedOut()
            },
            portalSessionSnapshotAction: {
                return await self.portalSessionCoordinator.snapshot()
            },
            coinWalletStore: self.coinWalletStore
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
