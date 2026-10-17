import BrowseCraftDomain
import CryptoKit
import FirebaseAnalytics
import Foundation

// 中文注释：AppAnalytics 专门封装用户行为采集，避免与 Crashlytics 诊断职责混在一起。
// 事件字典的唯一定义点是 docs/design/Analytics-Events-Design.md；本文件的 `Event` / `Parameter`
// 与它逐条对应，每个 case 的注释写三件事：何时触发、带哪些参数、刻意不报什么。
// 各事件的强类型上报方法按设计文档的 A–I 分组放在 AppAnalytics+*.swift。

final class AppAnalytics: Sendable {
    static let shared: AppAnalytics = AppAnalytics()
    static let collectionEnabledDefaultsKey: String = "settings.analyticsEnabled"

    enum Event: String, CaseIterable {
        // MARK: A. 应用与会话

        /// 冷启动、`configure()` 完成后报一次。`app_open` 是 Firebase 保留名，所以加 `bc_` 前缀。
        /// 参数：无。
        case appOpen = "bc_app_open"
        /// 从后台回到前台（scenePhase 变为 active）时报；冷启动那次不报。
        /// 参数：无。
        case appForegrounded = "app_foregrounded"
        /// 启动装配失败、进入启动失败页时报。
        /// 参数：error_code（装配失败在哪一步）。不报：诊断码与错误文案。
        case appBootstrapFailed = "app_bootstrap_failed"
        /// 开屏动画结束、退到标签页时报，记录为什么结束。
        /// 参数：result（StartupOutcome）、entry（落到哪个标签页）。
        case startupFinished = "startup_finished"
        /// 任一页面显示时报，含从下级页返回、盖在上面的 sheet / 全屏页关闭后重新露出；由 `.analyticsScreen(_:)` 统一发出。
        /// 参数：screen_name、screen_class（都取 DiagnosticScreen 的原始值）。
        case screenView = "screen_view"
        /// 用户点开规则生成结果推送时报；推送在前台到达不报。
        /// 参数：entry（固定为 rule_generation）。不报：推送内容与任务 ID。
        case pushOpened = "push_opened"
        /// 用户复制诊断码、账号 ID、启动失败信息或导出诊断日志时报，用来估计求助量。
        /// 参数：entry（SupportInfoKind）。不报：复制或导出的内容本身。
        case supportInfoCopied = "support_info_copied"

        // MARK: B. 来源与规则目录

        /// 当前来源切换成功时报，不论从哪里发起。
        /// 参数：content_kind、source_id_hash、entry（SourceSelectionEntry）。不报：来源名与网址。
        case sourceSelected = "source_selected"
        /// 从规则目录添加来源的结局：服务端返回、解密入库后报 success，任一步失败报 failed。
        /// 参数：content_kind、source_id_hash、entry（SourceAddEntry）、result、error_code（仅失败）。不报：来源名与网址。
        case sourceAdded = "source_added"
        /// 删除来源的撤销窗口结束、真正提交删除时报；被撤销的不报。
        /// 参数：content_kind、source_id_hash、entry（SourceDeleteEntry）。
        case sourceDeleted = "source_deleted"
        /// 用户点底部「撤销」恢复刚删的来源时报。
        /// 参数：content_kind、result。
        case sourceDeletionUndone = "source_deletion_undone"
        /// 启用已暂停来源的结局；从收藏、历史点到暂停来源弹出的启用窗口也算。
        /// 参数：content_kind、entry（SourceActivationEntry）、result（SourceActivationResult）。
        case sourceActivated = "source_activated"
        /// 点任一通往购买页的入口时报，算各入口的转化。
        /// 参数：entry（PremiumEntry）。
        case premiumEntryTapped = "premium_entry_tapped"
        /// 在「我的生成」左滑删除个人规则或失败记录时报。
        /// 参数：entry（CatalogItemKind）、result。
        case catalogItemDeleted = "catalog_item_deleted"
        /// 目录规则自动更新应用完成时报；没有可更新的不报。
        /// 参数：trigger（CatalogUpdateTrigger）、item_count_bucket（更新了几条）、result。
        case catalogRulesUpdated = "catalog_rules_updated"

        // MARK: C. 规则生成

        /// 添加来源页选定影视 / 漫画 / 书类型时报。
        /// 参数：content_kind。
        case generationKindSelected = "generation_kind_selected"
        /// 生成引导屏点「继续」或取消时报；回看引导关闭也报。
        /// 参数：entry（GenerationGuideEntry）、result（GenerationGuideResult）。
        case generationGuideFinished = "generation_guide_finished"
        /// 用户发起一次网址预检时报。
        /// 参数：content_kind、input_method（PreflightInputMethod）。不报：网址。
        case generationPreflightStarted = "generation_preflight_started"
        /// 预检得出结论、抛错或被用户取消时报一次。App 挡下的入口不会到服务器，算预检通过率只能靠它。
        /// 参数：content_kind、preflight_status、error_code、site_host_hash。不报：网址、路径与查询串。
        case generationPreflightResult = "generation_preflight_result"
        /// 滑动提交生成的结局，每次提交报一次（余额不足也在这里，取代原 `generation_insufficient_coins`）。
        /// 参数：content_kind、hard_mode、is_refresh、result（GenerationSubmitResult）、error_code。不报：余额与用户标识。
        case generationSubmitted = "generation_submitted"
        /// 提交成功后系统询问通知权限的结果。
        /// 参数：result（PushPermissionResult）。
        case pushPermissionResult = "push_permission_result"

        // MARK: D. 库、搜索与站点登录

        /// 库页切换分类 chip 时报。
        /// 参数：content_kind、source_id_hash。不报：分类名。
        case libraryCategorySelected = "library_category_selected"
        /// 来源内搜索提交后、第一页结果回来时报。
        /// 参数：content_kind、source_id_hash、result（SearchResult）、result_count_bucket。不报：搜索词。
        case searchSubmitted = "search_submitted"
        /// 打开作品详情页（或临时资源详情）时报，算各入口的分发量。
        /// 参数：content_kind、source_id_hash、entry（ContentOpenEntry）。不报：作品标题与网址。
        case contentOpened = "content_opened"
        /// 站点登录页关闭时报结局。
        /// 参数：content_kind、source_id_hash、entry（SourceLoginEntry）、result。不报：账号与 Cookie。
        case sourceLoginResult = "source_login_result"
        /// 库页长按「退出登录」清掉站点凭据时报。
        /// 参数：content_kind、source_id_hash。
        case sourceLogout = "source_logout"
        /// 加入收藏成功时报。
        /// 参数：content_kind、source_id_hash、entry（FavoriteEntry）。不报：作品标题。
        case favoriteAdded = "favorite_added"
        /// 取消收藏成功时报；批量取消只报一次。
        /// 参数：content_kind、source_id_hash（批量时不带）、entry（FavoriteEntry）、item_count_bucket。
        case favoriteRemoved = "favorite_removed"

        // MARK: E. 阅读与播放

        /// 漫画或书阅读器第一次加载成功时报；换章不再重复报。
        /// 参数：content_kind、source_id_hash、entry（ReaderOpenEntry）。
        case readerOpened = "reader_opened"
        /// 阅读器内进入新章节时报。
        /// 参数：content_kind、source_id_hash、navigation（ChapterNavigation）。不报：章节名。
        case chapterOpened = "chapter_opened"
        /// 离开阅读器时报一次汇总，取代逐页上报。
        /// 参数：content_kind、duration_bucket、item_count_bucket（本次读了几章）。
        case readerClosed = "reader_closed"
        /// 书阅读器里加书签时报；与「收藏」是两回事。
        /// 参数：content_kind。
        case readerBookmarkAdded = "reader_bookmark_added"
        /// 书阅读器里删书签时报。
        /// 参数：content_kind。
        case readerBookmarkRemoved = "reader_bookmark_removed"
        /// 视频、有声书或临时资源真正开始播放时报（视频取 `markReadyToPlay`）。
        /// 参数：content_kind、source_id_hash、player_type、entry（PlaybackEntry）。
        case playbackStarted = "playback_started"
        /// 播放层失败时报：直链播不出、网页播放器报提供方错误；规则解析失败仍走 I 组的诊断事件。
        /// 参数：content_kind、source_id_hash、player_type、error_code（PlaybackFailureCode）。
        case playbackFailed = "playback_failed"
        /// 原生播放器正常播完一集、有声书播完最后一章时报。
        /// 参数：content_kind、player_type。
        case playbackCompleted = "playback_completed"
        /// 关闭播放器时报一次汇总。
        /// 参数：content_kind、player_type、duration_bucket。
        case playbackClosed = "playback_closed"
        /// 网页播放器失败卡上点「重试」或「用浏览器打开」时报。
        /// 参数：entry（PlaybackFallbackAction）。
        case playbackFallbackTapped = "playback_fallback_tapped"
        /// 影视详情切换播放线路时报。
        /// 参数：source_id_hash。不报：线路名。
        case videoLineSwitched = "video_line_switched"
        /// 积分满 100、页面要弹激励广告时报（设计书 30.8）；去广告用户不累计积分，不会产生。
        /// 参数：ad_trigger。
        case adPointsThreshold = "ad_points_threshold"
        /// 一次激励广告的结局，自动唤起与设置页手动入口共用。
        /// 参数：ad_trigger、ad_result（含 busy：已有广告在播而跳过）、signed_in。不报：余额与用户标识。
        case rewardedAdResult = "rewarded_ad_result"
        /// 已登录看完广告后报一次：余额版本号前进即报，约 60 秒的轮询窗口结束仍没前进也报；轮询被又一次广告打断不报。
        /// 参数：result（AdRewardCreditResult：credited 窗口内版本号前进，timeout 窗口内没到账、之后仍可能到账）。不报：余额数值、迟到的到账。
        case adRewardCredited = "ad_reward_credited"
        /// 第一次播激励广告前弹出的跟踪授权（ATT）窗口关闭后报一次；状态已决定、不弹窗时不报。
        /// 参数：result（TrackingAuthorizationResult）。Analytics 本身不读 IDFA。
        case trackingAuthorizationResult = "tracking_authorization_result"

        // MARK: F. 收藏、历史与内容锁定

        /// 收藏页或历史页切换类型筛选时报。
        /// 参数：screen_name、content_kind（含 all）。
        case contentFilterChanged = "content_filter_changed"
        /// 收藏页或历史页进入选择模式时报。
        /// 参数：screen_name、entry（SelectionModeEntry）。
        case selectionModeEntered = "selection_mode_entered"
        /// 删除历史记录成功时报；批量删除只报一次。
        /// 参数：entry（HistoryDeleteEntry）、item_count_bucket。
        case historyDeleted = "history_deleted"
        /// 长按「在库中查看来源」时报。
        /// 参数：screen_name。
        case openInLibraryTapped = "open_in_library_tapped"
        /// 收藏 / 历史的面容 ID 解锁结局。
        /// 参数：trigger（ContentUnlockTrigger）、result。
        case contentUnlockResult = "content_unlock_result"

        // MARK: G. 账号、购买与删除账号

        /// 通过 Apple 登录的结局。
        /// 参数：result、error_code。不报：Apple / Portal 账号标识与邮箱。
        case signInResult = "sign_in_result"
        /// 退出账号成功时报；服务端拒绝 token、Apple 凭据被撤销导致的被动退出也报。
        /// 参数：trigger（SignOutTrigger）。
        case signOutCompleted = "sign_out_completed"
        /// 购买页加载商品的结局。
        /// 参数：result（PaywallLoadResult）。
        case paywallProductsLoaded = "paywall_products_loaded"
        /// 点方案、弹出 StoreKit 支付前报。
        /// 参数：product_id。不报：价格与订单号。
        case purchaseStarted = "purchase_started"
        /// 一次购买的结局，以服务端确认为准。
        /// 参数：product_id、result（PurchaseResult）、error_code。不报：订单号与交易 ID。
        case purchaseResult = "purchase_result"
        /// 恢复购买的结局。
        /// 参数：result（RestoreResult）。
        case restoreResult = "restore_result"
        /// 后台交易更新导致权益变化时报（非用户操作）。
        /// 参数：result（EntitlementChange）、product_id。
        case entitlementChanged = "entitlement_changed"
        /// 删除账号流程的结局；在确认框点取消或「保留账号」也报。
        /// 参数：result、error_code。
        case accountDeletionResult = "account_deletion_result"

        // MARK: H. 设置、同步与缓存

        /// 用户亲手改一项设置且生效时报；使用统计开关只报「打开」（关闭后什么都不报）。
        /// 参数：setting_name（AnalyticsSettingName）、setting_value。
        case settingChanged = "setting_changed"
        /// 设置页点「评分」或「隐私权政策」时报。
        /// 参数：entry（SettingsLink）。
        case settingsLinkOpened = "settings_link_opened"
        /// 清除图片缓存完成时报。
        /// 参数：size_bucket（释放的空间）。
        case cacheCleared = "cache_cleared"
        /// 首次启用云同步弹窗的选择与结局。
        /// 参数：entry（CloudSyncFirstEnableChoice）、result。
        case cloudSyncFirstEnableResult = "cloud_sync_first_enable_result"
        /// 一次云同步跑完时报。
        /// 参数：trigger（AnalyticsCloudSyncTrigger）、result。不报：同步了哪些记录。
        case cloudSyncRun = "cloud_sync_run"
        /// 登录后首次从 iCloud 恢复的结局；下拉重试的也报。
        /// 参数：trigger（CloudInitialRestoreTrigger）、result。
        case cloudInitialRestoreResult = "cloud_initial_restore_result"

        // MARK: I. 规则执行诊断

        /// 规则执行失败且分类器判为网络类时报；用户取消不报。
        /// 参数：rule_stage、error_code（RuleFailurePoint）、content_kind、source_id_hash。
        case networkRequestFailed = "network_request_failed"
        /// 规则执行失败且分类器判为解析类时报。
        /// 参数：同 network_request_failed。
        case parseFailed = "parse_failed"
    }

    enum Parameter {
        /// 页面名，取 `DiagnosticScreen` 的原始值。
        static let screenName: String = "screen_name"
        /// 页面类，与页面名同值。必须显式传：缺省时 Firebase 取当前 UIViewController 类名，SwiftUI 的类名超过 100 字符被判无效，连页面名一起丢掉。
        static let screenClass: String = "screen_class"
        /// 内容类型，取 `AnalyticsContentKind`。
        static let contentKind: String = "content_kind"
        /// 来源 ID 的 SHA-256，只用来按来源去重。
        static let sourceIdHash: String = "source_id_hash"
        /// 入口主机名小写后的 SHA-256。
        static let siteHostHash: String = "site_host_hash"
        /// 从哪里发起，取值随事件定义。
        static let entry: String = "entry"
        /// 非用户点击的起因，取值随事件定义。
        static let trigger: String = "trigger"
        /// 流程结局：通用 success / cancelled / failed，个别事件扩展。
        static let result: String = "result"
        /// 失败原因，snake_case 枚举（`AnalyticsErrorCode`）。
        static let errorCode: String = "error_code"
        /// 规则执行阶段，取 `DiagnosticRuleStage`（转 snake_case）。
        static let ruleStage: String = "rule_stage"
        /// 搜索结果数分桶：0 / 1_5 / 6_20 / 21_50 / 51_plus。
        static let resultCountBucket: String = "result_count_bucket"
        /// 批量操作或汇总的条数分桶，档位同上。
        static let itemCountBucket: String = "item_count_bucket"
        /// 停留或播放时长分桶：lt_1m / 1_5m / 5_15m / 15_30m / 30_60m / 60_120m / gt_120m。
        static let durationBucket: String = "duration_bucket"
        /// 释放空间分桶：lt_10mb / 10_100mb / 100_500mb / gt_500mb。
        static let sizeBucket: String = "size_bucket"
        /// 播放器类型：native / web / audio。
        static let playerType: String = "player_type"
        /// 换章方式：next / previous / toc / auto。
        static let navigation: String = "navigation"
        /// 网址怎么来的：typed / pasted / retry。
        static let inputMethod: String = "input_method"
        /// 是否「重新生成」。
        static let isRefresh: String = "is_refresh"
        /// 规则生成提交是否选了困难模式（`BC-ACQ-071`）。
        static let hardMode: String = "hard_mode"
        /// 预检结论：accepted / rejected / inconclusive / error / cancelled。
        static let preflightStatus: String = "preflight_status"
        /// 谁触发的广告：comic / video / book / audiobook / manual。
        static let adTrigger: String = "ad_trigger"
        /// 广告结局：completed / skipped / unavailable / failed / busy。
        static let adResult: String = "ad_result"
        /// 看广告时是否已登录（未登录看完不计 coin）。
        static let signedIn: String = "signed_in"
        /// App Store 商品 ID。
        static let productId: String = "product_id"
        /// 哪项设置，取 `AnalyticsSettingName`。
        static let settingName: String = "setting_name"
        /// 设置的新值：true / false / 缓存上限 MB。
        static let settingValue: String = "setting_value"
        /// 版本号，每个事件自动附带。
        static let appVersion: String = "app_version"
        /// 构建号，每个事件自动附带。
        static let buildNumber: String = "build_number"

        /// 参数白名单：不在表里的键一律丢弃（设计文档「参数字典」）。
        static let allowed: Set<String> = [
            Parameter.screenName,
            Parameter.screenClass,
            Parameter.contentKind,
            Parameter.sourceIdHash,
            Parameter.siteHostHash,
            Parameter.entry,
            Parameter.trigger,
            Parameter.result,
            Parameter.errorCode,
            Parameter.ruleStage,
            Parameter.resultCountBucket,
            Parameter.itemCountBucket,
            Parameter.durationBucket,
            Parameter.sizeBucket,
            Parameter.playerType,
            Parameter.navigation,
            Parameter.inputMethod,
            Parameter.isRefresh,
            Parameter.hardMode,
            Parameter.preflightStatus,
            Parameter.adTrigger,
            Parameter.adResult,
            Parameter.signedIn,
            Parameter.productId,
            Parameter.settingName,
            Parameter.settingValue,
            Parameter.appVersion,
            Parameter.buildNumber
        ]
    }

    private enum UserProperty {
        static let diagnosticCode: String = "diagnostic_code"
        static let appVersion: String = "app_version"
        static let buildNumber: String = "build_number"
    }

    private init() {}

    func configure(identityStore: DiagnosticIdentityStore = .shared) {
        let identity: DiagnosticIdentity = identityStore.identity

        Analytics.setAnalyticsCollectionEnabled(Self.isCollectionEnabled)
        Analytics.setUserID(identity.supportUserId)
        Analytics.setUserProperty(identity.diagnosticCode, forName: UserProperty.diagnosticCode)
        Analytics.setUserProperty(Self.appVersion, forName: UserProperty.appVersion)
        Analytics.setUserProperty(Self.buildNumber, forName: UserProperty.buildNumber)
    }

    /// 中文注释：「发送使用统计」开关。关闭后 `log()` 直接跳过，Firebase 的自动事件（含 AdMob 写入的广告事件）
    /// 也一并停止；打开时补报一次 `setting_changed`，关闭时什么都不报。
    func setCollectionEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: Self.collectionEnabledDefaultsKey)
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
        if isEnabled {
            self.logSettingChanged(.usageStatistics, value: "true")
        }
    }

    func log(_ event: Event, parameters: [String: Any] = [:]) {
        guard Self.isCollectionEnabled else {
            return
        }

        Analytics.logEvent(event.rawValue, parameters: Self.safeParameters(Self.baseParameters(parameters)))
    }

    static var isCollectionEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.collectionEnabledDefaultsKey) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: Self.collectionEnabledDefaultsKey)
    }

    // MARK: - 参数拼装

    /// 中文注释：内容类型与来源哈希是最常见的一对，统一在这里拼。
    static func sourceParameters(_ source: Source?, kind: AnalyticsContentKind? = nil) -> [String: Any] {
        var parameters: [String: Any] = [
            Parameter.contentKind: (kind ?? AnalyticsContentKind(source: source)).rawValue
        ]
        if let source: Source {
            parameters[Parameter.sourceIdHash] = Self.hashIdentifier(source.id)
        }
        return parameters
    }

    static func boolValue(_ value: Bool) -> String {
        return value ? "true" : "false"
    }

    private static func safeParameters(_ parameters: [String: Any]) -> [String: Any] {
        return parameters.filter { key, _ in
            return Parameter.allowed.contains(key)
        }
    }

    private static func baseParameters(_ parameters: [String: Any]) -> [String: Any] {
        var result: [String: Any] = parameters
        result[Parameter.appVersion] = Self.appVersion
        result[Parameter.buildNumber] = Self.buildNumber
        return result
    }

    // MARK: - 分桶与哈希

    static func countBucket(_ count: Int) -> String {
        switch count {
        case ..<1:
            return "0"
        case 1...5:
            return "1_5"
        case 6...20:
            return "6_20"
        case 21...50:
            return "21_50"
        default:
            return "51_plus"
        }
    }

    static func durationBucket(_ seconds: TimeInterval) -> String {
        let minutes: Double = seconds / 60
        switch minutes {
        case ..<1:
            return "lt_1m"
        case ..<5:
            return "1_5m"
        case ..<15:
            return "5_15m"
        case ..<30:
            return "15_30m"
        case ..<60:
            return "30_60m"
        case ..<120:
            return "60_120m"
        default:
            return "gt_120m"
        }
    }

    static func sizeBucket(bytes: Int64) -> String {
        let megabytes: Double = Double(bytes) / 1_048_576
        switch megabytes {
        case ..<10:
            return "lt_10mb"
        case ..<100:
            return "10_100mb"
        case ..<500:
            return "100_500mb"
        default:
            return "gt_500mb"
        }
    }

    /// 中文注释：主机名小写后取哈希；与 `source_id_hash` 同一哈希函数，按站去重用。
    static func hostHash(_ host: String?) -> String? {
        guard let host: String, host.isEmpty == false else {
            return nil
        }
        return Self.hashIdentifier(host.lowercased())
    }

    static func hashIdentifier(_ value: String) -> String {
        let digest: SHA256.Digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { byte in
            return String(format: "%02x", byte)
        }.joined()
    }

    private static var appVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private static var buildNumber: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }
}
