import Foundation

struct StoreTransactionSnapshot: Sendable {
    let transactionID: String
    let originalTransactionID: String
    let productID: String
    let productType: String
    let environment: PortalPurchaseEnvironment
    let environmentRawValue: String
    let ownershipType: String
    let appAccountToken: UUID?
    let purchaseDate: Date
    let expirationDate: Date?
    let revocationDate: Date?
}

/// Portal entitlement refresh, contract validation and local persistence are one application operation.
/// StoreKit is adapted to `StoreTransactionSnapshot` before crossing this boundary.
actor PortalPurchaseCoordinator {
    private let appUserRepository: AppUserRepository
    private let activeAppUser: any ActiveAppUserProviding
    private let identityAuthorizer: StoreKitPurchaseIdentityAuthorizer
    private let entitlementRefreshCoordinator: PortalPurchaseEntitlementRefreshCoordinator
    private let supportedProductIDs: Set<String>

    init(
        appUserRepository: AppUserRepository,
        activeAppUser: any ActiveAppUserProviding,
        identityAuthorizer: StoreKitPurchaseIdentityAuthorizer,
        entitlementRefreshCoordinator: PortalPurchaseEntitlementRefreshCoordinator,
        supportedProductIDs: Set<String>
    ) {
        self.appUserRepository = appUserRepository
        self.activeAppUser = activeAppUser
        self.identityAuthorizer = identityAuthorizer
        self.entitlementRefreshCoordinator = entitlementRefreshCoordinator
        self.supportedProductIDs = supportedProductIDs
    }

    func authorizeUserInitiatedAction() async throws -> UUID {
        return try await self.identityAuthorizer.authorizeUserInitiatedStoreKitAction()
    }

    func validateAuthorizedUser(_ userID: UUID) async throws {
        try await self.identityAuthorizer.validateAuthorizedUser(userID)
    }

    func submitPurchase(
        transaction: StoreTransactionSnapshot,
        signedTransaction: String,
        expectedProductID: String
    ) async throws -> Set<String> {
        let userID: UUID = self.activeAppUser.currentUserID
        try self.requireOwner(transaction, userID: userID)
        guard transaction.productID == expectedProductID else {
            throw StoreKitPortalPurchaseSubmissionError.transactionProductMismatch
        }

        let snapshot: PortalEntitlementSnapshot = try await self.entitlementRefreshCoordinator
            .refreshPurchasedEntitlements(
                userID: userID,
                environment: transaction.environment,
                signedTransaction: signedTransaction
            )
        try await self.identityAuthorizer.validateAuthorizedUser(userID)
        try self.validate(snapshot, userID: userID, purchasedProductID: expectedProductID)
        try self.persist(snapshot, transactions: [transaction])
        return snapshot.activeProductIDs
    }

    func submitUpdate(
        transaction: StoreTransactionSnapshot,
        signedTransaction: String,
        expectedProductID: String
    ) async throws -> Set<String> {
        let userID: UUID = self.activeAppUser.currentUserID
        try self.requireOwner(transaction, userID: userID)
        guard transaction.productID == expectedProductID else {
            throw StoreKitPortalPurchaseSubmissionError.transactionProductMismatch
        }

        let snapshot: PortalEntitlementSnapshot = try await self.entitlementRefreshCoordinator
            .refreshUpdatedEntitlements(
                userID: userID,
                environment: transaction.environment,
                signedTransaction: signedTransaction
            )
        try await self.identityAuthorizer.validateAuthorizedUser(userID)
        try self.validate(
            snapshot,
            userID: userID,
            updatedProductID: expectedProductID,
            isRevoked: transaction.revocationDate != nil
        )
        try self.persist(snapshot, transactions: [transaction])
        return snapshot.activeProductIDs
    }

    func restore(
        userID: UUID,
        environment: PortalPurchaseEnvironment,
        signedTransactions: [String],
        transactions: [StoreTransactionSnapshot]
    ) async throws -> Set<String> {
        try await self.identityAuthorizer.validateAuthorizedUser(userID)
        let snapshot: PortalEntitlementSnapshot = try await self.entitlementRefreshCoordinator
            .restoreEntitlements(
                userID: userID,
                environment: environment,
                signedTransactions: signedTransactions
            )
        try await self.identityAuthorizer.validateAuthorizedUser(userID)
        try self.validate(
            snapshot,
            userID: userID,
            restoredProductIDs: Set(transactions.map(\.productID))
        )
        try self.persist(snapshot, transactions: transactions)
        return snapshot.activeProductIDs
    }

    private func requireOwner(
        _ transaction: StoreTransactionSnapshot,
        userID: UUID
    ) throws {
        guard let appAccountToken: UUID = transaction.appAccountToken else {
            throw StoreKitTransactionIdentityError.missingAppAccountToken
        }
        guard appAccountToken == userID else {
            throw StoreKitTransactionIdentityError.accountMismatch
        }
    }

    private func validate(
        _ snapshot: PortalEntitlementSnapshot,
        userID: UUID
    ) throws {
        guard snapshot.userID == userID,
              snapshot.includedSiteSlots == SourceSlotPolicy.includedSiteSlotCount,
              snapshot.activeProductIDs.isSubset(of: self.supportedProductIDs) else {
            throw StoreKitPortalPurchaseSubmissionError.snapshotContractMismatch
        }
    }

    private func validate(
        _ snapshot: PortalEntitlementSnapshot,
        userID: UUID,
        purchasedProductID: String
    ) throws {
        try self.validate(snapshot, userID: userID)
        guard snapshot.activeProductIDs.contains(purchasedProductID) else {
            throw StoreKitPortalPurchaseSubmissionError.purchasedProductMissing
        }
    }

    private func validate(
        _ snapshot: PortalEntitlementSnapshot,
        userID: UUID,
        restoredProductIDs: Set<String>
    ) throws {
        try self.validate(snapshot, userID: userID)
        guard restoredProductIDs.isSubset(of: snapshot.activeProductIDs) else {
            throw StoreKitPortalPurchaseSubmissionError.snapshotContractMismatch
        }
    }

    private func validate(
        _ snapshot: PortalEntitlementSnapshot,
        userID: UUID,
        updatedProductID: String,
        isRevoked: Bool
    ) throws {
        try self.validate(snapshot, userID: userID)
        guard snapshot.activeProductIDs.contains(updatedProductID) != isRevoked else {
            throw StoreKitPortalPurchaseSubmissionError.snapshotContractMismatch
        }
    }

    private func persist(
        _ snapshot: PortalEntitlementSnapshot,
        transactions: [StoreTransactionSnapshot]
    ) throws {
        let now: Date = Date()
        let userID: String = snapshot.userID.uuidString
        var user: AppUser = try self.appUserRepository.fetchUser(id: userID) ?? AppUser(
            id: userID,
            displayName: nil,
            hasRemovedAds: false,
            pendingAdPoints: 0,
            createdAt: now,
            updatedAt: now
        )
        user.hasRemovedAds = snapshot.hasRemovedAds
        user.purchasedSiteSlots = snapshot.purchasedSiteSlots
        user.siteSlotLimit = snapshot.siteSlotLimit
        user.updatedAt = now

        if let latest: StoreTransactionSnapshot = transactions.max(by: {
            $0.purchaseDate < $1.purchaseDate
        }) {
            user.lastStoreKitTransactionID = latest.transactionID
            user.lastStoreKitOriginalTransactionID = latest.originalTransactionID
            user.lastStoreKitProductID = latest.productID
            user.lastStoreKitProductType = latest.productType
            user.lastStoreKitEnvironment = latest.environmentRawValue
            user.lastStoreKitOwnershipType = latest.ownershipType
            user.lastStoreKitPurchaseDate = latest.purchaseDate
            user.lastStoreKitExpirationDate = latest.expirationDate
            user.lastStoreKitRevocationDate = latest.revocationDate
        }

        var newTransactions: [UserStoreKitTransaction] = []
        for transaction: StoreTransactionSnapshot in transactions {
            guard try self.appUserRepository.hasProcessedStoreKitTransaction(
                userID: userID,
                transactionID: transaction.transactionID
            ) == false else {
                continue
            }
            newTransactions.append(
                UserStoreKitTransaction(
                    userID: userID,
                    transactionID: transaction.transactionID,
                    originalTransactionID: transaction.originalTransactionID,
                    productID: transaction.productID,
                    productType: transaction.productType,
                    environment: transaction.environmentRawValue,
                    ownershipType: transaction.ownershipType,
                    purchaseDate: transaction.purchaseDate,
                    expirationDate: transaction.expirationDate,
                    revocationDate: transaction.revocationDate,
                    createdAt: now
                )
            )
        }
        try self.appUserRepository.saveUser(user, storeKitTransactions: newTransactions)
    }
}
