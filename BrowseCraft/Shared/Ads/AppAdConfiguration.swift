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

    /// 中文注释：AdMob 测试设备哈希（project.yml `BROWSECRAFT_AD_TEST_DEVICE_IDS`，逗号分隔）。
    /// 真实广告单元 + 测试设备：看到的仍是测试广告、不算无效流量，但 SSV 回调照发——验证 coin 到账靠它。
    static var testDeviceIdentifiers: [String] {
        return self.infoString(forKey: "BrowseCraftAdTestDeviceIdentifiers")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private static func infoString(forKey key: String) -> String {
        return (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }
}
