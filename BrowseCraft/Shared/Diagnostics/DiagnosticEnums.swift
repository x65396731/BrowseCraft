import BrowseCraftDomain
import Foundation

// 中文注释：诊断枚举集中定义 Firebase 字段取值，避免散落字符串造成查询口径不一致。

/// 中文注释：页面名，Crashlytics 的当前页面键与 Analytics 的 `screen_name` 共用（设计文档「界面覆盖盘点」）。
/// 34 个用户可达页面各一个 case，原始值 snake_case；由 `.analyticsScreen(_:)` 统一上报。
enum DiagnosticScreen: String {
    // 启动
    /// 开屏动画。
    case startup
    /// 启动失败页。
    case bootstrapFailure = "bootstrap_failure"

    // 标签页
    /// 来源页。
    case sources
    /// 收藏页。
    case favorites
    /// 库页。
    case library
    /// 历史页。
    case history
    /// 设置页。
    case settings

    // 来源
    /// 规则目录（sheet）。
    case catalog
    /// 添加来源·选类型（sheet）。
    case addSource = "add_source"
    /// 生成引导屏。
    case entryGuide = "entry_guide"
    /// 网址输入·生成。
    case generationInput = "generation_input"
    /// 启用来源窗口（sheet）。
    case sourceActivation = "source_activation"
    /// 来源详情（只读调试页）。
    case sourceDebug = "source_debug"

    // 库
    /// 来源内搜索（sheet）。
    case librarySearch = "library_search"
    /// 站点登录（全屏）。
    case sourceLogin = "source_login"
    /// 漫画详情。
    case comicDetail = "comic_detail"
    /// 漫画阅读器。
    case comicReader = "comic_reader"
    /// 影视详情。
    case videoDetail = "video_detail"
    /// 视频播放器（全屏）。
    case videoPlayer = "video_player"
    /// 站点书详情。
    case bookDetail = "book_detail"
    /// 书阅读器。
    case bookReader = "book_reader"
    /// 有声书播放。
    case audiobookPlayer = "audiobook_player"
    /// 本地书架（入口已藏）。
    case bookShelf = "book_shelf"

    // 收藏与历史
    /// 临时资源详情。
    case temporaryDetail = "temporary_detail"
    /// 临时资源播放器（网页 / 原生）。
    case temporaryPlayer = "temporary_player"
    /// 漫画资源网页。
    case comicResourceWeb = "comic_resource_web"
    /// 历史不可用提示页。
    case historyUnavailable = "history_unavailable"
    /// 收藏 / 历史的内容锁定遮罩。
    case contentLocked = "content_locked"

    // 设置
    /// 购买页（全屏层）。
    case purchase
    /// 缓存。
    case cacheSettings = "cache_settings"
    /// 云同步。
    case cloudSync = "cloud_sync"
    /// 首次启用云同步（sheet）。
    case cloudSyncFirstEnable = "cloud_sync_first_enable"
    /// coin 记录。
    case coinLedger = "coin_ledger"
    /// 删除账号。
    case accountDeletion = "account_deletion"
    /// 报告问题面板（sheet，Problem-Report-Design.md 第四节），从库页与三种详情页打开。
    case problemReport = "problem_report"
}

enum DiagnosticSourceType: String {
    case comic
    case video
    case book
    case unknown
}

enum DiagnosticRuleStage: String {
    case search
    case list
    case detail
    case chapter
    case reader
    case videoPlayback
    case unknown
}

extension Source {
    var diagnosticSourceType: DiagnosticSourceType {
        switch self.configuration.kind {
        case .comic:
            return .comic
        case .video:
            return .video
        case .plugin:
            return .unknown
        case .book:
            return .book
        }
    }
}

/// 中文注释：诊断上报只需要区分「网络类」与「解析类」两个桶。判定规则错误属于哪一桶要认
/// `RuleExecutionError`，那是 Application 的分类器的职责；Shared 只接收已判定的结果，
/// 因此本枚举是纯取值、不含任何判定逻辑。（2026-09-18 收敛边界豁免时引入。）
enum DiagnosticFailureKind: String {
    case network
    case parse
}
