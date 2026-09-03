import Foundation

// 中文注释：广告 ID 由 project.yml 按 Debug/Release 写入生成的 Info.plist。
enum AppAdConfiguration {
    static var environmentName: String {
        return self.infoString(forKey: "BrowseCraftEnvironmentName")
    }

    static var isProduction: Bool {
        return self.environmentName == "PROD"
    }

    static var adMobApplicationID: String {
        return self.infoString(forKey: "GADApplicationIdentifier")
    }

    static var hasAdMobApplicationID: Bool {
        return self.adMobApplicationID.isEmpty == false
    }

    static var rewardedAdUnitID: String {
        return self.infoString(forKey: "BrowseCraftRewardedAdUnitID")
    }

    static var hasRewardedAdUnit: Bool {
        return self.rewardedAdUnitID.isEmpty == false
    }

    private static func infoString(forKey key: String) -> String {
        return (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }
}
