import Foundation

// 中文注释：问题报告的封闭取值（docs/design/Problem-Report-Design.md 第三、五节，`BCA-OBS-021`）。
// 放在 Shared：报文（Application）、面板（Features）与埋点参数（AppAnalytics）共用同一份原始值；
// PortalCore `app/modules/problem_reports/contracts.py` 逐条照抄，先改合同再两边同改。

/// 中文注释：报告对象（合同第三节）。
enum ProblemReportScope: String, Hashable, Sendable {
    /// 库页的列表、当前分类与翻页。
    case list
    /// 详情页的详情与目录。
    case detail
    /// 某一集（话、章）的内容，只从详情页报。
    case content
}

/// 中文注释：从哪个入口打开面板（合同第六节 `entry`）。
enum ProblemReportEntry: String, Hashable, Sendable {
    case failureState = "failure_state"
    case pageMenu = "page_menu"
}

/// 中文注释：发送失败的原因（`problem_report_submitted` 的 `error_code`）。
enum ProblemReportFailureCode: String, Hashable, Sendable {
    /// 服务端回 429，超出次数上限。
    case rateLimited = "rate_limited"
    /// 网络或服务端错误。
    case sendFailed = "send_failed"
}

/// 中文注释：合同第五节的 30 个问题码。显示文字按内容类型换词，码不变。
enum ProblemReportProblemType: String, Hashable, Sendable, CaseIterable {
    case loadFailed = "load_failed"
    case playbackFailed = "playback_failed"
    case listEmpty = "list_empty"
    case coverMissing = "cover_missing"
    case titleWrong = "title_wrong"
    case latestWrong = "latest_wrong"
    case categoryWrong = "category_wrong"
    case paginationWrong = "pagination_wrong"
    case garbledText = "garbled_text"
    case tocEmpty = "toc_empty"
    case tocIncomplete = "toc_incomplete"
    case linesMixed = "lines_mixed"
    case orderWrong = "order_wrong"
    case lockUnmarked = "lock_unmarked"
    case infoWrong = "info_wrong"
    case wrongItem = "wrong_item"
    case adsOrRedirect = "ads_or_redirect"
    case webFallback = "web_fallback"
    case stuckLoading = "stuck_loading"
    case allLinesFailed = "all_lines_failed"
    case paywallAfterLogin = "paywall_after_login"
    case contentEmpty = "content_empty"
    case imagesNotLoading = "images_not_loading"
    case contentMissing = "content_missing"
    case nonContentImages = "non_content_images"
    case slow
    case chapterPartial = "chapter_partial"
    case junkText = "junk_text"
    case progressWrong = "progress_wrong"
    case other
}
