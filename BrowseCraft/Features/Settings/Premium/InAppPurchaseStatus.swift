import Foundation

enum InAppPurchaseStatus: Equatable {
    case idle
    case loadingProducts
    case productsUnavailable
    case someProductsUnavailable
    case productLoadFailed
    case productUnavailable(title: String)
    case checkingIdentity
    case portalSignInRequired
    case identityMismatch
    case identityCheckFailed
    case restoreAccountMismatch
    case purchasing(productID: String, title: String)
    case submittingPurchase(productID: String, title: String)
    case pending(productID: String, title: String)
    case cancelled
    case unverified(title: String)
    case alreadyPurchased(title: String)
    case purchaseFailed(title: String)
    case transactionIdentityMismatch(title: String)
    case xcodeEnvironmentUnsupported(title: String)
    case storeKitEnvironmentUnsupported(title: String)
    case portalSessionUnavailable(title: String)
    case portalTemporarilyUnavailable(title: String)
    case portalAccountMismatch(title: String)
    case portalTransactionClaimed(title: String)
    case portalSubmissionRejected(title: String)
    case portalOutcomeUnknown(title: String)
    case portalSubmissionInterrupted(title: String)
    case purchased(title: String)
    case restoring
    case restored
    case restoreFailed
    case revoked(title: String)

    var message: String? {
        switch self {
        case .idle: return nil
        case .loadingProducts: return "Loading StoreKit products…"
        case .productsUnavailable: return "No StoreKit products are currently available."
        case .someProductsUnavailable: return "Some StoreKit products are currently unavailable."
        case .productLoadFailed: return "StoreKit products could not be loaded."
        case .productUnavailable(let title): return "\(title) is not currently available for purchase."
        case .checkingIdentity: return "Checking your BrowseCraft account…"
        case .portalSignInRequired: return "Sign in with Apple before purchasing or restoring purchases."
        case .identityMismatch: return "The active BrowseCraft account changed. Sign in again before continuing."
        case .identityCheckFailed: return "The BrowseCraft account could not be verified. Sign in again and retry."
        case .restoreAccountMismatch: return "Some App Store purchases belong to another BrowseCraft profile and were not restored to this account."
        case .purchasing(_, let title): return "Purchasing \(title)…"
        case .submittingPurchase(_, let title): return "Verifying \(title) with BrowseCraft…"
        case .pending(_, let title): return "\(title) is awaiting approval. No entitlement has been applied."
        case .cancelled: return "Purchase cancelled. No entitlement was applied."
        case .unverified(let title): return "\(title) could not be verified. No entitlement was applied."
        case .alreadyPurchased(let title): return "\(title) is already purchased. Use Restore Purchases to sync its entitlement."
        case .purchaseFailed(let title): return "\(title) could not be purchased."
        case .transactionIdentityMismatch(let title): return "\(title) is not bound to the active BrowseCraft profile. No entitlement was applied."
        case .xcodeEnvironmentUnsupported(let title): return "\(title) is an Xcode StoreKit test purchase. It was not sent to Portal; use App Store Sandbox for server verification."
        case .storeKitEnvironmentUnsupported(let title): return "\(title) came from an unsupported StoreKit environment and was not sent to Portal."
        case .portalSessionUnavailable(let title): return "\(title) completed in the App Store, but the Portal session is unavailable. Use Restore Purchases to recover it."
        case .portalTemporarilyUnavailable(let title): return "\(title) completed in the App Store, but Portal verification is temporarily unavailable. Use Restore Purchases later."
        case .portalAccountMismatch(let title): return "\(title) was rejected because the Portal or Apple transaction account does not match this BrowseCraft profile."
        case .portalTransactionClaimed(let title): return "\(title) is already bound to another BrowseCraft profile. No entitlement was applied."
        case .portalSubmissionRejected(let title): return "\(title) was rejected by Portal. No entitlement was applied."
        case .portalOutcomeUnknown(let title): return "\(title) completed in the App Store, but its Portal entitlement result is unknown. Use Restore Purchases before buying again."
        case .portalSubmissionInterrupted(let title): return "\(title) completed in the App Store, but Portal verification was interrupted. Use Restore Purchases to continue."
        case .purchased(let title): return "\(title) purchase completed."
        case .restoring: return "Restoring purchases…"
        case .restored: return "Purchases restored."
        case .restoreFailed: return "Purchases could not be restored."
        case .revoked(let title): return "\(title) was revoked or refunded."
        }
    }

    var isInProgress: Bool {
        switch self {
        case .loadingProducts, .checkingIdentity, .purchasing, .submittingPurchase, .restoring:
            return true
        default:
            return false
        }
    }

    var suspendsBackgroundAnimation: Bool {
        switch self {
        case .checkingIdentity, .purchasing, .submittingPurchase, .restoring:
            return true
        default:
            return false
        }
    }

    var diagnosticCode: String {
        switch self {
        case .idle: return "idle"
        case .loadingProducts: return "loading-products"
        case .productsUnavailable: return "products-unavailable"
        case .someProductsUnavailable: return "some-products-unavailable"
        case .productLoadFailed: return "product-load-failed"
        case .productUnavailable: return "product-unavailable"
        case .checkingIdentity: return "checking-identity"
        case .portalSignInRequired: return "portal-sign-in-required"
        case .identityMismatch: return "identity-mismatch"
        case .identityCheckFailed: return "identity-check-failed"
        case .restoreAccountMismatch: return "restore-account-mismatch"
        case .purchasing: return "purchasing"
        case .submittingPurchase: return "submitting-purchase"
        case .pending: return "pending"
        case .cancelled: return "cancelled"
        case .unverified: return "unverified"
        case .alreadyPurchased: return "already-purchased"
        case .purchaseFailed: return "purchase-failed"
        case .transactionIdentityMismatch: return "transaction-identity-mismatch"
        case .xcodeEnvironmentUnsupported: return "xcode-environment-unsupported"
        case .storeKitEnvironmentUnsupported: return "storekit-environment-unsupported"
        case .portalSessionUnavailable: return "portal-session-unavailable"
        case .portalTemporarilyUnavailable: return "portal-temporarily-unavailable"
        case .portalAccountMismatch: return "portal-account-mismatch"
        case .portalTransactionClaimed: return "portal-transaction-claimed"
        case .portalSubmissionRejected: return "portal-submission-rejected"
        case .portalOutcomeUnknown: return "portal-outcome-unknown"
        case .portalSubmissionInterrupted: return "portal-submission-interrupted"
        case .purchased: return "purchased"
        case .restoring: return "restoring"
        case .restored: return "restored"
        case .restoreFailed: return "restore-failed"
        case .revoked: return "revoked"
        }
    }
}
