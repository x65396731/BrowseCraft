import Foundation

struct InAppPurchasePlan: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let productID: String
    let fallbackPrice: String
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
        fallbackPrice: String,
        siteSlotIncrement: Int = 0,
        vipMonthDuration: Int = 0,
        removesAds: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.productID = productID
        self.fallbackPrice = fallbackPrice
        self.siteSlotIncrement = siteSlotIncrement
        self.vipMonthDuration = vipMonthDuration
        self.removesAds = removesAds
    }

    static let year: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Year",
        subtitle: "Best value for full access",
        systemImage: "calendar.badge.clock",
        productID: "browsecraft.premium.year",
        fallbackPrice: "$19.99",
        vipMonthDuration: 12
    )

    static let quarter: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Quarter",
        subtitle: "Flexible seasonal access",
        systemImage: "calendar",
        productID: "browsecraft.premium.quarter",
        fallbackPrice: "$6.99",
        vipMonthDuration: 3
    )

    static let month: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Month",
        subtitle: "Try premium features first",
        systemImage: "calendar.badge.plus",
        productID: "browsecraft.premium.month",
        fallbackPrice: "$2.99",
        vipMonthDuration: 1
    )

    static let siteSlot1: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Site Slot",
        subtitle: "Add one custom site position",
        systemImage: "square.grid.2x2",
        productID: "browsecraft.site.slot.1",
        fallbackPrice: "$0.99",
        siteSlotIncrement: 1
    )

    static let siteSlot5: InAppPurchasePlan = InAppPurchasePlan(
        title: "5 Site Slots",
        subtitle: "Add five custom site positions",
        systemImage: "square.grid.3x2",
        productID: "browsecraft.site.slot.5",
        fallbackPrice: "$3.99",
        siteSlotIncrement: 5
    )

    static let siteSlot10: InAppPurchasePlan = InAppPurchasePlan(
        title: "10 Site Slots",
        subtitle: "Add ten custom site positions",
        systemImage: "square.grid.3x3",
        productID: "browsecraft.site.slot.10",
        fallbackPrice: "$6.99",
        siteSlotIncrement: 10
    )

    static let siteSlot30: InAppPurchasePlan = InAppPurchasePlan(
        title: "30 Site Slots",
        subtitle: "Add thirty custom site positions",
        systemImage: "rectangle.grid.3x2",
        productID: "browsecraft.site.slot.30",
        fallbackPrice: "$14.99",
        siteSlotIncrement: 30
    )

    static let removeAds: InAppPurchasePlan = InAppPurchasePlan(
        title: "Remove Ads",
        subtitle: "Hide rewarded ad prompts permanently",
        systemImage: "nosign",
        productID: "browsecraft.remove.ads",
        fallbackPrice: "$4.99",
        removesAds: true
    )

    static let allPlans: [InAppPurchasePlan] = [
        .year,
        .quarter,
        .month,
        .siteSlot1,
        .siteSlot5,
        .siteSlot10,
        .siteSlot30,
        .removeAds
    ]
}
