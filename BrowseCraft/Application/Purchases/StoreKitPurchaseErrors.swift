import Foundation

// 中文注释：StoreKit 交易与 Portal 提交的错误合同由 Application 层持有；
// PortalPurchaseCoordinator 抛出、PortalIAPServicing 分类，Feature 只做展示映射。

enum StoreKitTransactionIdentityError: Error, Equatable {
    case missingAppAccountToken
    case accountMismatch
}

enum StoreKitPortalPurchaseSubmissionError: Error, Equatable {
    case xcodeEnvironmentUnsupported
    case unsupportedEnvironment(String)
    case transactionProductMismatch
    case snapshotContractMismatch
    case purchasedProductMissing
}
