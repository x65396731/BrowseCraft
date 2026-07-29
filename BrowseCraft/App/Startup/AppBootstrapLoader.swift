import Foundation

struct AppBootstrapDependencies: @unchecked Sendable {
    let database: AppDatabase
    let activeUserID: UUID
}

/// Potentially slow database migration and identity bootstrap happen before MainActor composition.
actor AppBootstrapLoader {
    func load() throws -> AppBootstrapDependencies {
        let database: AppDatabase = try AppDatabase()
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
