import Foundation

/// 中文注释：启动时先固定 Keychain 身份，再幂等补齐数据库用户；数据库失败后可在下次启动重试。
struct AppUserIdentityBootstrapper {
    private let identityStore: any AppUserIdentityStoring
    private let appUserRepository: any AppUserRepository
    private let makeUserID: () -> UUID
    private let now: () -> Date

    init(
        identityStore: any AppUserIdentityStoring,
        appUserRepository: any AppUserRepository,
        makeUserID: @escaping () -> UUID = UUID.init,
        now: @escaping () -> Date = Date.init
    ) {
        self.identityStore = identityStore
        self.appUserRepository = appUserRepository
        self.makeUserID = makeUserID
        self.now = now
    }

    func bootstrap() throws -> UUID {
        let userID: UUID

        if let storedUserID: UUID = try self.identityStore.loadUserID() {
            userID = storedUserID
        } else {
            let generatedUserID: UUID = self.makeUserID()
            try self.identityStore.saveUserID(generatedUserID)
            userID = generatedUserID
        }

        try self.ensureAppUserExists(userID: userID)
        return userID
    }

    private func ensureAppUserExists(userID: UUID) throws {
        let databaseID: String = userID.uuidString
        guard try self.appUserRepository.fetchUser(id: databaseID) == nil else {
            return
        }

        let timestamp: Date = self.now()
        try self.appUserRepository.saveUser(
            AppUser(
                id: databaseID,
                displayName: nil,
                hasRemovedAds: false,
                pendingAdPoints: 0,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        )
    }
}
