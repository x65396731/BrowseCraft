struct SettingsFeatureFactory {
    private let database: AppDatabase
    private let imageCacheConfigurator: ImageCacheConfigurator
    private let cloudAccountSession: CloudAccountSession
    private let cloudAccountPartitionStore: any CloudAccountPartitioning
    private let cloudSyncCoordinator: CloudSyncCoordinator

    init(
        database: AppDatabase,
        imageCacheConfigurator: ImageCacheConfigurator,
        cloudAccountSession: CloudAccountSession,
        cloudAccountPartitionStore: any CloudAccountPartitioning,
        cloudSyncCoordinator: CloudSyncCoordinator
    ) {
        self.database = database
        self.imageCacheConfigurator = imageCacheConfigurator
        self.cloudAccountSession = cloudAccountSession
        self.cloudAccountPartitionStore = cloudAccountPartitionStore
        self.cloudSyncCoordinator = cloudSyncCoordinator
    }

    func makeViewModel() -> SettingsViewModel {
        return SettingsViewModel(
            imageCacheConfigurator: self.imageCacheConfigurator,
            appUserRepository: GRDBAppUserRepository(database: self.database)
        )
    }

    @MainActor
    func makeCloudSyncViewModel() -> CloudSyncSettingsViewModel {
        return CloudSyncSettingsViewModel(
            accountSession: self.cloudAccountSession,
            partitionStore: self.cloudAccountPartitionStore,
            coordinator: self.cloudSyncCoordinator
        )
    }
}
