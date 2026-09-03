import Foundation

// 中文注释：AppUserRepository 负责本地用户根状态的读取和保存。
protocol AppUserRepository: Sendable {
    func fetchUser(id: String) throws -> AppUser?
    func hasProcessedStoreKitTransaction(userID: String, transactionID: String) throws -> Bool
    func saveUser(_ user: AppUser) throws
    func saveUser(_ user: AppUser, storeKitTransaction: UserStoreKitTransaction) throws
    func saveUser(
        _ user: AppUser,
        storeKitTransactions: [UserStoreKitTransaction]
    ) throws
}

extension AppUserRepository {
    func saveUser(
        _ user: AppUser,
        storeKitTransactions: [UserStoreKitTransaction]
    ) throws {
        guard storeKitTransactions.isEmpty == false else {
            try self.saveUser(user)
            return
        }
        for transaction: UserStoreKitTransaction in storeKitTransactions {
            try self.saveUser(user, storeKitTransaction: transaction)
        }
    }
}
