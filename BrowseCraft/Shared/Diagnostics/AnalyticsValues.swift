import BrowseCraftDomain
import Foundation

// 中文注释：埋点参数的取值全部集中在这里（Claude 文档「BrowseCraft 埋点事件审计与全覆盖设计」，
// 入库合同见 docs/design/Analytics-Events-Design.md）。调用点只传这些枚举，不传裸字符串；
// 原始值一律 snake_case，就是上报到 Firebase 的字面值。新增取值先改设计文档再改这里。

/// 中文注释：参数 `content_kind`——内容类型。有声书单列；`all` 只用于收藏 / 历史的类型筛选。
enum AnalyticsContentKind: String, Sendable {
    case comic
    case video
    case book
    case audiobook
    case all
    case unknown

    init(source: Source?) {
        guard let source: Source else {
            self = .unknown
            return
        }
        switch source.configuration.kind {
        case .comic:
            self = .comic
        case .video:
            self = .video
        case .book:
            self = .book
        case .plugin:
            self = .unknown
        }
    }

    init(ruleGenerationKind: RuleGenerationSourceKind) {
        switch ruleGenerationKind {
        case .video:
            self = .video
        case .comic:
            self = .comic
        case .book:
            self = .book
        }
    }
}

/// 中文注释：参数 `result` 的通用取值；个别事件有自己的结局枚举（见下）。
enum AnalyticsResult: String, Sendable {
    case success
    case cancelled
    case failed
}

/// 中文注释：参数 `error_code`。只能从字符串原始值的枚举构造，保证上报的是有限取值而不是错误文案；
/// 原始值是 camelCase 的（如 Domain 的预检原因）在这里统一转成 snake_case。
struct AnalyticsErrorCode: Sendable, Equatable {
    let value: String

    init<Code: RawRepresentable>(_ code: Code) where Code.RawValue == String {
        self.value = AnalyticsErrorCode.snakeCased(code.rawValue)
    }

    /// 中文注释：camelCase / kebab-case → snake_case；连续大写当一个词（`unsafeURL` → `unsafe_url`，`URLPath` → `url_path`）。
    static func snakeCased(_ raw: String) -> String {
        let characters: [Character] = Array(raw)
        var result: String = ""
        for (index, character) in characters.enumerated() {
            if character == "-" || character == " " {
                result.append("_")
                continue
            }
            guard character.isUppercase else {
                result.append(character)
                continue
            }
            let previous: Character? = index > 0 ? characters[index - 1] : nil
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            let startsWord: Bool = previous.map { $0.isLowercase || $0.isNumber } ?? false
            let endsAcronym: Bool = (previous?.isUppercase ?? false) && (next?.isLowercase ?? false)
            if (startsWord || endsAcronym) && result.last != "_" {
                result.append("_")
            }
            result.append(contentsOf: character.lowercased())
        }
        return result
    }
}

/// 中文注释：`network_request_failed` / `parse_failed` 的 `error_code`——规则执行在哪个调用点失败。
enum RuleFailurePoint: String, Sendable {
    case libraryRefresh = "library_refresh"
    case libraryPagination = "library_pagination"
    case librarySearch = "library_search"
    case librarySearchPagination = "library_search_pagination"
    case libraryFavoriteState = "library_favorite_state"
    case sourceSelectRefresh = "source_select_refresh"
    case sourceRefresh = "source_refresh"
    case comicDetail = "comic_detail"
    case comicReader = "comic_reader"
    case videoDetail = "video_detail"
    case videoEpisodeResolve = "video_episode_resolve"
    case videoPlayback = "video_playback"
    case bookDetail = "book_detail"
    case bookReaderOpen = "book_reader_open"
}

// MARK: - A. 应用与会话

/// 中文注释：`startup_finished` 的 `result`——开屏为什么结束。
enum StartupOutcome: String, Sendable {
    /// 用户点了「跳过」。
    case skipped
    /// 来源加载完成，正常结束。
    case loaded
    /// 没有任何来源。
    case noSources = "no_sources"
    /// 检查来源失败。
    case sourceCheckFailed = "source_check_failed"
    /// 来源加载超过 15 秒。
    case timedOut = "timed_out"
    /// 库页初次加载失败。
    case sourceLoadFailed = "source_load_failed"
    /// 开屏视频播放失败。
    case videoFailed = "video_failed"
}

/// 中文注释：`startup_finished` 的 `entry`——开屏结束后落到哪个标签页。
enum AnalyticsTab: String, Sendable {
    case sources
    case favorites
    case library
    case history
    case settings
}

/// 中文注释：`support_info_copied` 的 `entry`——复制了哪种求助信息。
enum SupportInfoKind: String, Sendable {
    case diagnosticCode = "diagnostic_code"
    case accountID = "account_id"
    case bootstrapFailure = "bootstrap_failure"
    /// 设置页导出诊断日志（Logging-Design.md BCA-OBS-016）。
    case diagnosticLog = "diagnostic_log"
}

/// 中文注释：`app_bootstrap_failed` 的 `error_code`——启动装配在哪一步失败。
enum BootstrapFailureStage: String, Sendable {
    case database
    case container
    case unknown
}

// MARK: - B. 来源与规则目录

/// 中文注释：`source_selected` 的 `entry`。
enum SourceSelectionEntry: String, Sendable {
    /// 来源页点卡片或「切换并打开库」。
    case sourcesList = "sources_list"
    /// 从规则目录添加后自动切过去。
    case catalogAdd = "catalog_add"
    /// 收藏 / 历史长按「在库中查看来源」。
    case openInLibrary = "open_in_library"
    /// 启用暂停来源后切过去。
    case activation
}

/// 中文注释：`source_added` 的 `entry`——在规则目录的哪一块点的添加。
enum SourceAddEntry: String, Sendable {
    case recommended
    case kindSection = "kind_section"
    case myGenerations = "my_generations"
}

/// 中文注释：`source_deleted` 的 `entry`。
enum SourceDeleteEntry: String, Sendable {
    case swipe
    case menu
}

/// 中文注释：`source_activated` 的 `entry`——从哪里点到了暂停的来源。
enum SourceActivationEntry: String, Sendable {
    case sourcesList = "sources_list"
    case favorites
    case history
}

/// 中文注释：`source_activated` 的 `result`。
enum SourceActivationResult: String, Sendable {
    /// 有空位，直接启用。
    case success
    /// 换下了另一个来源。
    case replaced
    case cancelled
    case failed
}

/// 中文注释：`premium_entry_tapped` 的 `entry`——从哪个入口进的购买页。
enum PremiumEntry: String, Sendable {
    /// 来源页位置条「更多」。
    case slotBar = "slot_bar"
    /// 位置已满提示「获取更多位置」。
    case slotFull = "slot_full"
    /// 启用来源窗口「获取更多位置」。
    case activationSheet = "activation_sheet"
    /// 设置页高级版卡片。
    case settingsCard = "settings_card"
}

/// 中文注释：`catalog_item_deleted` 的 `entry`。
enum CatalogItemKind: String, Sendable {
    case personalRule = "personal_rule"
    case failedOutcome = "failed_outcome"
}

/// 中文注释：`catalog_rules_updated` 的 `trigger`。
enum CatalogUpdateTrigger: String, Sendable {
    case catalogOpen = "catalog_open"
    case foreground
}

// MARK: - C. 规则生成

/// 中文注释：`generation_guide_finished` 的 `entry`。
enum GenerationGuideEntry: String, Sendable {
    /// 首次必过的引导。
    case firstRun = "first_run"
    /// 从「怎样的页面能生成」等入口回看。
    case help
}

/// 中文注释：`generation_guide_finished` 的 `result`。
enum GenerationGuideResult: String, Sendable {
    case continued
    case cancelled
}

/// 中文注释：`generation_preflight_started` 的 `input_method`。
enum PreflightInputMethod: String, Sendable {
    case typed
    case pasted
    case retry
}

/// 中文注释：`generation_submitted` 的 `result`——一次提交的结局。
enum GenerationSubmitResult: String, Sendable {
    case submitted
    /// 复用现成规则并扣 coin。
    case reused
    case insufficientCoins = "insufficient_coins"
    case authRequired = "auth_required"
    case activeJobLimit = "active_job_limit"
    case previousJobActive = "previous_job_active"
    case rateLimited = "rate_limited"
    case failed
    /// App 本地拒绝或异常，没到服务端。
    case localRejected = "local_rejected"
}

/// 中文注释：`push_permission_result` 的 `result`。
enum PushPermissionResult: String, Sendable {
    case granted
    case denied
    /// 之前已经决定过，这次没有弹窗。
    case alreadyDecided = "already_decided"
}

// MARK: - D. 库、搜索与站点登录

/// 中文注释：`search_submitted` 的 `result`。
enum SearchResult: String, Sendable {
    case success
    case failed
    case loginRequired = "login_required"
}

/// 中文注释：`content_opened` 的 `entry`——从哪里打开了作品详情。
enum ContentOpenEntry: String, Sendable {
    case library
    case search
    case favorites
    case history
    case continueTile = "continue_tile"
    case temporary
}

/// 中文注释：`source_login_result` 的 `entry`——在哪个页面弹出的站点登录。
enum SourceLoginEntry: String, Sendable {
    case library
    case search
    case detail
    case reader
    case player
}

/// 中文注释：`favorite_added` / `favorite_removed` 的 `entry`。
enum FavoriteEntry: String, Sendable {
    case library
    case search
    case detail
    case favoritesSwipe = "favorites_swipe"
    case favoritesMenu = "favorites_menu"
    case favoritesBatch = "favorites_batch"
}

// MARK: - E. 阅读与播放

/// 中文注释：`reader_opened` 的 `entry`。
enum ReaderOpenEntry: String, Sendable {
    case detailStart = "detail_start"
    case detailContinue = "detail_continue"
    case chapterList = "chapter_list"
    case history
    case continueTile = "continue_tile"
}

/// 中文注释：`chapter_opened` 的 `navigation`——怎么进的新章。
enum ChapterNavigation: String, Sendable {
    case next
    case previous
    case toc
    /// 阅读中自然进入下一章（书的连续阅读）。
    case auto
}

/// 中文注释：参数 `player_type`。
enum PlayerType: String, Sendable {
    case native
    case web
    case audio
}

/// 中文注释：`playback_started` 的 `entry`。
enum PlaybackEntry: String, Sendable {
    case episode
    case `continue`
    case history
    case continueTile = "continue_tile"
    case temporary
}

/// 中文注释：`playback_failed` 的 `error_code`——播放层的失败类别。
enum PlaybackFailureCode: String, Sendable {
    case nativeFailed = "native_failed"
    case blocked
    case unreachable
    case sourceInvalid = "source_invalid"
    case providerError = "provider_error"
    case unavailable
}

/// 中文注释：`playback_fallback_tapped` 的 `entry`。
enum PlaybackFallbackAction: String, Sendable {
    case retry
    case openInBrowser = "open_in_browser"
}

/// 中文注释：`ad_reward_credited` 的 `result`。窗口长度见 `CoinWalletStore.adRewardPollDelays`（约 60 秒）。
enum AdRewardCreditResult: String, Sendable {
    /// 轮询窗口内余额版本号前进了（不区分原因，窗口内其他余额变化也算）。
    case credited
    /// 轮询窗口内版本号没前进。不等于没到账：SSV 回调晚于窗口时余额照样会到，只是这次轮询没看到，也不补报。
    case timeout
}

/// 中文注释：`tracking_authorization_result` 的 `result`——ATT 弹窗的选择。
enum TrackingAuthorizationResult: String, Sendable {
    case authorized
    case denied
    case restricted
}

// MARK: - F. 收藏、历史与内容锁定

/// 中文注释：`selection_mode_entered` 的 `entry`。
enum SelectionModeEntry: String, Sendable {
    case headerButton = "header_button"
    case longPress = "long_press"
}

/// 中文注释：`history_deleted` 的 `entry`。
enum HistoryDeleteEntry: String, Sendable {
    case swipe
    case menu
    case batch
}

/// 中文注释：`content_unlock_result` 的 `trigger`。
enum ContentUnlockTrigger: String, Sendable {
    case button
    case tabSwitch = "tab_switch"
    case foreground
}

// MARK: - G. 账号、购买与删除账号

/// 中文注释：`sign_out_completed` 的 `trigger`。
enum SignOutTrigger: String, Sendable {
    case user
    /// 服务端拒绝 token 导致的被动退出。
    case tokenRejected = "token_rejected"
    /// Apple 凭据被撤销（用户在系统设置里停用「通过 Apple 登录」）导致的退出。
    case appleCredentialRevoked = "apple_credential_revoked"
}

/// 中文注释：`paywall_products_loaded` 的 `result`。
enum PaywallLoadResult: String, Sendable {
    case available
    case partial
    case unavailable
    case failed
}

/// 中文注释：`purchase_result` 的 `result`。
enum PurchaseResult: String, Sendable {
    case success
    case cancelled
    /// 待批准（家长同意等）。
    case pending
    case alreadyOwned = "already_owned"
    case refunded
    case failed
}

/// 中文注释：`restore_result` 的 `result`。
enum RestoreResult: String, Sendable {
    case success
    case nothingToRestore = "nothing_to_restore"
    case accountMismatch = "account_mismatch"
    case refunded
    case failed
}

/// 中文注释：`entitlement_changed` 的 `result`。
enum EntitlementChange: String, Sendable {
    case pendingApproved = "pending_approved"
    case revoked
}

// MARK: - H. 设置、同步与缓存

/// 中文注释：`setting_changed` 的 `setting_name`。
enum AnalyticsSettingName: String, Sendable {
    case contentLock = "content_lock"
    case crashDiagnostics = "crash_diagnostics"
    case usageStatistics = "usage_statistics"
    case imageCacheLimit = "image_cache_limit"
    case cloudSync = "cloud_sync"
}

/// 中文注释：`settings_link_opened` 的 `entry`。
enum SettingsLink: String, Sendable {
    case rateApp = "rate_app"
    case privacyPolicy = "privacy_policy"
}

/// 中文注释：`cloud_sync_first_enable_result` 的 `entry`——首次启用时选的合并方式。
enum CloudSyncFirstEnableChoice: String, Sendable {
    case mergeLocal = "merge_local"
    case cloudOnly = "cloud_only"
    case noLocalData = "no_local_data"
}

/// 中文注释：`cloud_sync_run` 的 `trigger`。
enum AnalyticsCloudSyncTrigger: String, Sendable {
    case pull
    case background
    case silentPush = "silent_push"
}

/// 中文注释：`cloud_initial_restore_result` 的 `trigger`。
enum CloudInitialRestoreTrigger: String, Sendable {
    case auto
    case pullRetry = "pull_retry"
}
