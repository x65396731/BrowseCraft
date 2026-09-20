import Foundation
import Testing
@testable import BrowseCraft
import BrowseCraftDomain

/// 合格入口页引导屏（`BC-PAGE-060` 的产品侧教程）：呈现时机、失败回流判定、三语文案齐备。
@MainActor
struct EntryPageGuideTests {
    @Test("没看过引导时呈现")
    func presentsWhenNeverSeen() {
        #expect(EntryPageGuide.shouldPresent(seenVersion: 0, didAcknowledge: false) == true)
    }

    @Test("看过当前版本后不再拦路")
    func skipsWhenSeenCurrentVersion() {
        #expect(
            EntryPageGuide.shouldPresent(
                seenVersion: EntryPageGuide.currentVersion,
                didAcknowledge: false
            ) == false
        )
    }

    @Test("只看过更早一版时再看一次")
    func presentsAgainAfterVersionBump() {
        #expect(
            EntryPageGuide.shouldPresent(
                seenVersion: EntryPageGuide.currentVersion - 1,
                didAcknowledge: false
            ) == true
        )
    }

    @Test("本次点过继续就不再呈现")
    func skipsAfterAcknowledgeInSameSession() {
        #expect(EntryPageGuide.shouldPresent(seenVersion: 0, didAcknowledge: true) == false)
    }

    /// 中文注释：四种入口页拒因说的都是「换一个合格的页面」，失败行要挂教程入口。
    @Test("四种入口页拒因都认成入口页问题")
    func recognizesEntryPageRejections() {
        for detail: String in VideoGenerationOutcomeText.entryPageRejectionDetails {
            #expect(VideoGenerationOutcomeText.isEntryPageRejection(Self.outcome(detail: detail)) == true)
        }
    }

    @Test("其它细分与缺失细分都不挂教程入口")
    func ignoresOtherReasonDetails() {
        #expect(VideoGenerationOutcomeText.isEntryPageRejection(Self.outcome(detail: "noPlaybackCarrier")) == false)
        #expect(VideoGenerationOutcomeText.isEntryPageRejection(Self.outcome(detail: nil)) == false)
        #expect(VideoGenerationOutcomeText.isEntryPageRejection(Self.outcome(detail: "somethingNewFromServer")) == false)
    }

    /// 中文注释：入口页拒因并进 `knownReasonDetails`，否则那一句细分文案会被整个吞掉。
    @Test("入口页拒因仍在可显示的细分表里")
    func entryPageDetailsRemainDisplayable() {
        for detail: String in VideoGenerationOutcomeText.entryPageRejectionDetails {
            #expect(VideoGenerationOutcomeText.knownReasonDetails.contains(detail))
            #expect(VideoGenerationOutcomeText.reasonDetailText(for: Self.outcome(detail: detail)) != nil)
        }
    }

    /// 中文注释：`NSLocalizedString` 查不到键时原样返回键名——用它验三份 strings 都补齐了。
    @Test("引导屏用到的文案键都有翻译")
    func guideStringsAreLocalized() {
        let keys: [String] = [
            "entry_guide_title", "entry_guide_subtitle", "entry_guide_requirements_title",
            "entry_guide_rule_pagination_title", "entry_guide_rule_pagination_detail",
            "entry_guide_rule_single_list_title", "entry_guide_rule_single_list_detail",
            "entry_guide_examples_title", "entry_guide_example_bad",
            "entry_guide_example_good_video", "entry_guide_example_good_comic",
            "entry_guide_example_good_book", "entry_guide_example_good_generic",
            "entry_guide_steps_title", "entry_guide_step_1", "entry_guide_step_2",
            "entry_guide_step_3", "entry_guide_continue_button", "entry_guide_dismiss_button",
            "entry_guide_reopen_link", "entry_guide_open_from_failure"
        ]
        for key: String in keys {
            #expect(NSLocalizedString(key, comment: "") != key, "缺翻译：\(key)")
        }
    }

    private static func outcome(detail: String?) -> VideoGenerationOutcome {
        return VideoGenerationOutcome(
            jobID: UUID(),
            entryURL: "https://example.com/list/1.html",
            status: "failed",
            finishedAt: nil,
            catalogSourceID: nil,
            reason: "siteNotSupported",
            reasonDetail: detail
        )
    }
}
