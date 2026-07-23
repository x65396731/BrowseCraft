import Foundation

// 中文注释：AppReviewPromptPolicy 只管理本机评分请求资格，不依赖分析开关或用户账号。
@MainActor
final class AppReviewPromptPolicy {
    static let shared: AppReviewPromptPolicy = AppReviewPromptPolicy()
    static let requiredSuccessfulContentOpenCount: Int = 5

    private enum Key {
        static let successfulContentOpenCountPrefix: String =
            "appReview.successfulContentOpenCount"
        static let lastRequestedVersion: String = "appReview.lastRequestedVersion"
    }

    private let userDefaults: UserDefaults
    private let currentVersionProvider: () -> String

    init(
        userDefaults: UserDefaults = .standard,
        currentVersionProvider: @escaping () -> String = {
            return Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown"
        }
    ) {
        self.userDefaults = userDefaults
        self.currentVersionProvider = currentVersionProvider
    }

    /// 中文注释：记录一次成功内容打开；返回值仅表示已达到阈值，不代表资格已被消耗。
    @discardableResult
    func recordSuccessfulContentOpen() -> Bool {
        guard self.hasRequestedReviewForCurrentVersion == false else {
            return false
        }

        let countKey: String = self.successfulContentOpenCountKey
        let currentCount: Int = self.userDefaults.integer(forKey: countKey)
        let updatedCount: Int = min(
            currentCount + 1,
            Self.requiredSuccessfulContentOpenCount
        )
        self.userDefaults.set(updatedCount, forKey: countKey)
        return updatedCount >= Self.requiredSuccessfulContentOpenCount
    }

    /// 中文注释：延迟结束后原子领取资格；成功时立即记录版本，防止重复请求。
    func consumeReviewRequestEligibility() -> Bool {
        guard self.hasRequestedReviewForCurrentVersion == false,
              self.successfulContentOpenCount >= Self.requiredSuccessfulContentOpenCount else {
            return false
        }

        self.userDefaults.set(
            self.currentVersion,
            forKey: Key.lastRequestedVersion
        )
        self.userDefaults.removeObject(forKey: self.successfulContentOpenCountKey)
        return true
    }

    var successfulContentOpenCount: Int {
        return self.userDefaults.integer(forKey: self.successfulContentOpenCountKey)
    }

    var hasRequestedReviewForCurrentVersion: Bool {
        return self.userDefaults.string(forKey: Key.lastRequestedVersion) ==
            self.currentVersion
    }

    private var currentVersion: String {
        return self.currentVersionProvider()
    }

    private var successfulContentOpenCountKey: String {
        return "\(Key.successfulContentOpenCountPrefix).\(self.currentVersion)"
    }
}
