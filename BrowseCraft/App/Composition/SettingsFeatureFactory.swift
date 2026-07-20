struct SettingsFeatureFactory {
    private let database: AppDatabase
    private let imageCacheConfigurator: ImageCacheConfigurator

    init(database: AppDatabase, imageCacheConfigurator: ImageCacheConfigurator) {
        self.database = database
        self.imageCacheConfigurator = imageCacheConfigurator
    }

    func makeViewModel() -> SettingsViewModel {
        return SettingsViewModel(
            imageCacheConfigurator: self.imageCacheConfigurator,
            appUserRepository: GRDBAppUserRepository(database: self.database)
        )
    }
}
