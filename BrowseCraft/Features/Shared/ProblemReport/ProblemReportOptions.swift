import Foundation

// 中文注释：每组的问题类型与显示文字（docs/design/Problem-Report-Design.md 第五节，`BCA-OBS-021`）。
// 每组不超过 9 个，「其他」总在最后；显示文字按内容类型换词（集 / 话 / 章），问题码不变。

enum ProblemReportOptions {
    static func types(
        scope: ProblemReportScope,
        kind: DiagnosticSourceType,
        isAudiobook: Bool
    ) -> [ProblemReportProblemType] {
        switch scope {
        case .list:
            return [.loadFailed, .listEmpty, .coverMissing, .titleWrong, .latestWrong, .categoryWrong, .paginationWrong, .garbledText, .other]
        case .detail:
            switch kind {
            case .video:
                return [.loadFailed, .tocEmpty, .tocIncomplete, .linesMixed, .orderWrong, .infoWrong, .coverMissing, .other]
            case .comic:
                return [.loadFailed, .tocEmpty, .tocIncomplete, .orderWrong, .lockUnmarked, .infoWrong, .coverMissing, .other]
            case .book, .unknown:
                return [.loadFailed, .tocEmpty, .tocIncomplete, .orderWrong, .garbledText, .infoWrong, .coverMissing, .other]
            }
        case .content:
            switch kind {
            case .video:
                return [.playbackFailed, .wrongItem, .adsOrRedirect, .webFallback, .stuckLoading, .allLinesFailed, .paywallAfterLogin, .other]
            case .comic:
                return [.loadFailed, .contentEmpty, .imagesNotLoading, .contentMissing, .orderWrong, .nonContentImages, .paywallAfterLogin, .slow, .other]
            case .book, .unknown:
                if isAudiobook {
                    return [.playbackFailed, .wrongItem, .progressWrong, .paywallAfterLogin, .other]
                }
                return [.loadFailed, .contentEmpty, .contentMissing, .chapterPartial, .junkText, .garbledText, .wrongItem, .other]
            }
        }
    }

    static func title(
        for type: ProblemReportProblemType,
        scope: ProblemReportScope,
        kind: DiagnosticSourceType,
        isAudiobook: Bool
    ) -> String {
        let key: String
        switch type {
        case .loadFailed:
            key = scope == .content ? "problem_type_open_failed" : "problem_type_load_failed"
        case .playbackFailed:
            key = "problem_type_playback_failed"
        case .listEmpty:
            key = "problem_type_list_empty"
        case .coverMissing:
            key = "problem_type_cover_missing"
        case .titleWrong:
            key = "problem_type_title_wrong"
        case .latestWrong:
            key = "problem_type_latest_wrong"
        case .categoryWrong:
            key = "problem_type_category_wrong"
        case .paginationWrong:
            key = "problem_type_pagination_wrong"
        case .garbledText:
            key = scope == .detail ? "problem_type_chapter_name_garbled" : "problem_type_garbled_text"
        case .tocEmpty:
            key = Self.byKind(kind, video: "problem_type_toc_empty_video", comic: "problem_type_toc_empty_comic", book: "problem_type_toc_empty_book")
        case .tocIncomplete:
            key = Self.byKind(kind, video: "problem_type_toc_incomplete_video", comic: "problem_type_toc_incomplete_comic", book: "problem_type_toc_incomplete_book")
        case .linesMixed:
            key = "problem_type_lines_mixed"
        case .orderWrong:
            key = scope == .detail && kind == .video ? "problem_type_order_wrong" : "problem_type_order_messed"
        case .lockUnmarked:
            key = "problem_type_lock_unmarked"
        case .infoWrong:
            key = "problem_type_info_wrong"
        case .wrongItem:
            key = kind == .video ? "problem_type_wrong_episode" : "problem_type_wrong_chapter"
        case .adsOrRedirect:
            key = "problem_type_ads_or_redirect"
        case .webFallback:
            key = "problem_type_web_fallback"
        case .stuckLoading:
            key = "problem_type_stuck_loading"
        case .allLinesFailed:
            key = "problem_type_all_lines_failed"
        case .paywallAfterLogin:
            key = isAudiobook ? "problem_type_paywall_after_login_listen" : "problem_type_paywall_after_login"
        case .contentEmpty:
            key = kind == .comic ? "problem_type_no_pages" : "problem_type_blank_chapter"
        case .imagesNotLoading:
            key = "problem_type_images_not_loading"
        case .contentMissing:
            key = kind == .comic ? "problem_type_missing_pages" : "problem_type_missing_paragraphs"
        case .nonContentImages:
            key = "problem_type_non_content_images"
        case .slow:
            key = "problem_type_slow"
        case .chapterPartial:
            key = "problem_type_chapter_partial"
        case .junkText:
            key = "problem_type_junk_text"
        case .progressWrong:
            key = "problem_type_progress_wrong"
        case .other:
            key = "problem_type_other"
        }
        return NSLocalizedString(key, comment: "问题报告：问题类型")
    }

    /// 中文注释：「某一集 / 某一话 / 某一章的内容」与「哪一集 / 话 / 章」的量词。
    static func contentAreaTitle(kind: DiagnosticSourceType) -> String {
        return NSLocalizedString(
            Self.byKind(kind, video: "problem_report_area_content_video", comic: "problem_report_area_content_comic", book: "problem_report_area_content_book"),
            comment: "问题报告：问题出在某一集的内容"
        )
    }

    static func episodeRowTitle(kind: DiagnosticSourceType) -> String {
        return NSLocalizedString(
            Self.byKind(kind, video: "problem_report_episode_video", comic: "problem_report_episode_comic", book: "problem_report_episode_book"),
            comment: "问题报告：哪一集"
        )
    }

    private static func byKind(_ kind: DiagnosticSourceType, video: String, comic: String, book: String) -> String {
        switch kind {
        case .video:
            return video
        case .comic:
            return comic
        case .book, .unknown:
            return book
        }
    }
}
