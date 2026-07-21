import Foundation

struct InAppPurchasePlan: Identifiable {
    enum ProductKind: Equatable {
        case consumable
        case nonConsumable
        case nonRenewingSubscription
    }

    let title: String
    let subtitle: String
    let systemImage: String
    let productID: String
    let productKind: ProductKind
    let siteSlotIncrement: Int
    let vipMonthDuration: Int
    let removesAds: Bool

    var id: String {
        return self.productID
    }

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        productID: String,
        productKind: ProductKind,
        siteSlotIncrement: Int = 0,
        vipMonthDuration: Int = 0,
        removesAds: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.productID = productID
        self.productKind = productKind
        self.siteSlotIncrement = siteSlotIncrement
        self.vipMonthDuration = vipMonthDuration
        self.removesAds = removesAds
    }

    static let year: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Year Premium",
        subtitle: "Best value for full access",
        systemImage: "calendar.badge.clock",
        productID: "com.xiefei.AnyPortal.premium.year",
        productKind: .nonRenewingSubscription,
        vipMonthDuration: 12
    )

    static let quarter: InAppPurchasePlan = InAppPurchasePlan(
        title: "3 Months Premium",
        subtitle: "Flexible seasonal access",
        systemImage: "calendar",
        productID: "com.xiefei.AnyPortal.premium.quarter",
        productKind: .nonRenewingSubscription,
        vipMonthDuration: 3
    )

    static let month: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Month Premium",
        subtitle: "Try premium features first",
        systemImage: "calendar.badge.plus",
        productID: "com.xiefei.AnyPortal.premium.month",
        productKind: .nonRenewingSubscription,
        vipMonthDuration: 1
    )

    static let siteSlot1: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Site Slot",
        subtitle: "Add one custom site slot",
        systemImage: "square.grid.2x2",
        productID: "com.xiefei.AnyPortal.site.unlock.1",
        productKind: .nonConsumable,
        siteSlotIncrement: 1
    )

    static let siteSlot5: InAppPurchasePlan = InAppPurchasePlan(
        title: "5 Site Slots",
        subtitle: "Add five custom site slots",
        systemImage: "square.grid.3x2",
        productID: "com.xiefei.AnyPortal.site.unlock.5",
        productKind: .nonConsumable,
        siteSlotIncrement: 5
    )

    static let siteSlot10: InAppPurchasePlan = InAppPurchasePlan(
        title: "10 Site Slots",
        subtitle: "Add ten custom site slots",
        systemImage: "square.grid.3x3",
        productID: "com.xiefei.AnyPortal.site.unlock.10",
        productKind: .nonConsumable,
        siteSlotIncrement: 10
    )

    static let siteSlot30: InAppPurchasePlan = InAppPurchasePlan(
        title: "30 Site Slots",
        subtitle: "Add thirty custom site slots",
        systemImage: "rectangle.grid.3x2",
        productID: "com.xiefei.AnyPortal.site.unlock.30",
        productKind: .nonConsumable,
        siteSlotIncrement: 30
    )

    static let removeAds: InAppPurchasePlan = InAppPurchasePlan(
        title: "Remove Ads",
        subtitle: "Hide rewarded ad prompts permanently",
        systemImage: "nosign",
        productID: "com.xiefei.AnyPortal.remove.ads",
        productKind: .nonConsumable,
        removesAds: true
    )

    /// Products that are currently available for display and new purchases.
    static let activePlans: [InAppPurchasePlan] = [
        .siteSlot1,
        .siteSlot5,
        .siteSlot10,
        .siteSlot30,
        .removeAds
    ]

    /// Products hidden from new purchases but retained for transaction compatibility.
    static let inactivePlans: [InAppPurchasePlan] = [
        .year,
        .quarter,
        .month
    ]

    /// Every trusted product ID that the app can recognize in existing transactions.
    static let knownPlans: [InAppPurchasePlan] = Self.activePlans + Self.inactivePlans

    static let plansByProductID: [String: InAppPurchasePlan] = Dictionary(
        uniqueKeysWithValues: Self.knownPlans.map { plan in
            return (plan.productID, plan)
        }
    )

    var isRestorable: Bool {
        switch self.productKind {
        case .consumable:
            return false
        case .nonConsumable, .nonRenewingSubscription:
            return true
        }
    }
}
