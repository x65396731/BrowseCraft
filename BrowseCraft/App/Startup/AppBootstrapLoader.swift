import Foundation

struct AppBootstrapDependencies: Sendable {
    let database: AppDatabase
    let activeUserID: UUID
}

/// Potentially slow database migration and identity bootstrap happen before MainActor composition.
actor AppBootstrapLoader {
    func load() throws -> AppBootstrapDependencies {
        #if DEBUG
        // 中文注释：演示模式用每次重建的独立库，真实库不打开也不写入。
        let database: AppDatabase = DemoMode.isEnabled
            ? try AppDatabase(path: DemoMode.freshDatabasePath())
            : try AppDatabase()
        #else
        let database: AppDatabase = try AppDatabase()
        #endif
        let activeUserID: UUID = try AppUserIdentityBootstrapper(
            identityStore: KeychainAppUserIdentityStore(),
            appUserRepository: GRDBAppUserRepository(database: database)
        ).bootstrap()
        return AppBootstrapDependencies(
            database: database,
            activeUserID: activeUserID
        )
    }
}
