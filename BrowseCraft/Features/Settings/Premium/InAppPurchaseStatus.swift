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
        case .loadingProducts: return NSLocalizedString("iap_status_loading_products", comment: "")
        case .productsUnavailable: return NSLocalizedString("iap_status_products_unavailable", comment: "")
        case .someProductsUnavailable: return NSLocalizedString("iap_status_some_products_unavailable", comment: "")
        case .productLoadFailed: return NSLocalizedString("iap_status_product_load_failed", comment: "")
        case .productUnavailable(let title): return String(format: NSLocalizedString("iap_status_product_unavailable", comment: ""), title)
        case .checkingIdentity: return NSLocalizedString("iap_status_checking_identity", comment: "")
        case .portalSignInRequired: return NSLocalizedString("iap_status_portal_sign_in_required", comment: "")
        case .identityMismatch: return NSLocalizedString("iap_status_identity_mismatch", comment: "")
        case .identityCheckFailed: return NSLocalizedString("iap_status_identity_check_failed", comment: "")
        case .restoreAccountMismatch: return NSLocalizedString("iap_status_restore_account_mismatch", comment: "")
        case .purchasing(_, let title): return String(format: NSLocalizedString("iap_status_purchasing", comment: ""), title)
        case .submittingPurchase(_, let title): return String(format: NSLocalizedString("iap_status_submitting_purchase", comment: ""), title)
        case .pending(_, let title): return String(format: NSLocalizedString("iap_status_pending", comment: ""), title)
        case .cancelled: return NSLocalizedString("iap_status_cancelled", comment: "")
        case .unverified(let title): return String(format: NSLocalizedString("iap_status_unverified", comment: ""), title)
        case .alreadyPurchased(let title): return String(format: NSLocalizedString("iap_status_already_purchased", comment: ""), title)
        case .purchaseFailed(let title): return String(format: NSLocalizedString("iap_status_purchase_failed", comment: ""), title)
        case .transactionIdentityMismatch(let title): return String(format: NSLocalizedString("iap_status_transaction_identity_mismatch", comment: ""), title)
        case .xcodeEnvironmentUnsupported(let title): return String(format: NSLocalizedString("iap_status_xcode_environment_unsupported", comment: ""), title)
        case .storeKitEnvironmentUnsupported(let title): return String(format: NSLocalizedString("iap_status_storekit_environment_unsupported", comment: ""), title)
        case .portalSessionUnavailable(let title): return String(format: NSLocalizedString("iap_status_portal_session_unavailable", comment: ""), title)
        case .portalTemporarilyUnavailable(let title): return String(format: NSLocalizedString("iap_status_portal_temporarily_unavailable", comment: ""), title)
        case .portalAccountMismatch(let title): return String(format: NSLocalizedString("iap_status_portal_account_mismatch", comment: ""), title)
        case .portalTransactionClaimed(let title): return String(format: NSLocalizedString("iap_status_portal_transaction_claimed", comment: ""), title)
        case .portalSubmissionRejected(let title): return String(format: NSLocalizedString("iap_status_portal_submission_rejected", comment: ""), title)
        case .portalOutcomeUnknown(let title): return String(format: NSLocalizedString("iap_status_portal_outcome_unknown", comment: ""), title)
        case .portalSubmissionInterrupted(let title): return String(format: NSLocalizedString("iap_status_portal_submission_interrupted", comment: ""), title)
        case .purchased(let title): return String(format: NSLocalizedString("iap_status_purchased", comment: ""), title)
        case .restoring: return NSLocalizedString("iap_status_restoring", comment: "")
        case .restored: return NSLocalizedString("iap_status_restored", comment: "")
        case .restoreFailed: return NSLocalizedString("iap_status_restore_failed", comment: "")
        case .revoked(let title): return String(format: NSLocalizedString("iap_status_revoked", comment: ""), title)
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

// MARK: - 埋点

extension InAppPurchaseStatus {
    /// 中文注释：购买流程结束时的 `purchase_result`；进行中与跟购买无关的状态返回 nil。
    var purchaseAnalyticsResult: PurchaseResult? {
        switch self {
        case .purchased:
            return .success
        case .cancelled:
            return .cancelled
        case .pending:
            return .pending
        case .alreadyPurchased:
            return .alreadyOwned
        case .revoked:
            return .refunded
        case .idle, .loadingProducts, .productsUnavailable, .someProductsUnavailable, .productLoadFailed,
             .checkingIdentity, .purchasing, .submittingPurchase, .restoring, .restored, .restoreFailed,
             .restoreAccountMismatch:
            return nil
        case .productUnavailable, .portalSignInRequired, .identityMismatch, .identityCheckFailed, .unverified,
             .purchaseFailed, .transactionIdentityMismatch, .xcodeEnvironmentUnsupported,
             .storeKitEnvironmentUnsupported, .portalSessionUnavailable, .portalTemporarilyUnavailable,
             .portalAccountMismatch, .portalTransactionClaimed, .portalSubmissionRejected, .portalOutcomeUnknown,
             .portalSubmissionInterrupted:
            return .failed
        }
    }

    /// 中文注释：恢复购买结束时的 `restore_result`；「没有可恢复」由调用方按恢复动作的返回值区分。
    var restoreAnalyticsResult: RestoreResult? {
        switch self {
        case .restored:
            return .success
        case .restoreAccountMismatch:
            return .accountMismatch
        case .revoked:
            return .refunded
        case .idle, .loadingProducts, .checkingIdentity, .purchasing, .submittingPurchase, .restoring:
            return nil
        default:
            return .failed
        }
    }

    /// 中文注释：失败时的 `error_code`，取状态本身（有限取值），不带标题等文案。
    var analyticsFailureCode: AnalyticsErrorCode? {
        guard let code: PurchaseFailureCode = PurchaseFailureCode(rawValue: self.diagnosticCode) else {
            return nil
        }
        return AnalyticsErrorCode(code)
    }
}

/// 中文注释：`AnalyticsErrorCode` 只收字符串原始值的枚举；原始值与 `InAppPurchaseStatus.diagnosticCode` 一致，上报时转成 snake_case。
private enum PurchaseFailureCode: String {
    case productUnavailable = "product-unavailable"
    case portalSignInRequired = "portal-sign-in-required"
    case identityMismatch = "identity-mismatch"
    case identityCheckFailed = "identity-check-failed"
    case restoreAccountMismatch = "restore-account-mismatch"
    case unverified
    case purchaseFailed = "purchase-failed"
    case transactionIdentityMismatch = "transaction-identity-mismatch"
    case xcodeEnvironmentUnsupported = "xcode-environment-unsupported"
    case storeKitEnvironmentUnsupported = "storekit-environment-unsupported"
    case portalSessionUnavailable = "portal-session-unavailable"
    case portalTemporarilyUnavailable = "portal-temporarily-unavailable"
    case portalAccountMismatch = "portal-account-mismatch"
    case portalTransactionClaimed = "portal-transaction-claimed"
    case portalSubmissionRejected = "portal-submission-rejected"
    case portalOutcomeUnknown = "portal-outcome-unknown"
    case portalSubmissionInterrupted = "portal-submission-interrupted"
    case restoreFailed = "restore-failed"
}
