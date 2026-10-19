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

    /// 中文注释：fwq `APP-MEMO-045`——只有首页入口的下一步是换页，失败行只给它挂教程入口。
    @Test("首页入口拒因挂教程入口")
    func showsGuideForSiteRoot() {
        #expect(VideoGenerationOutcomeText.showsEntryGuide(Self.outcome(detail: "entryPageIsSiteRoot")) == true)
    }

    @Test("其余入口页拒因、其它细分与缺失细分都不挂教程入口")
    func ignoresOtherReasonDetails() {
        for detail: String in VideoGenerationOutcomeText.entryPageRejectionDetails where detail != "entryPageIsSiteRoot" {
            #expect(VideoGenerationOutcomeText.showsEntryGuide(Self.outcome(detail: detail)) == false)
        }
        #expect(VideoGenerationOutcomeText.showsEntryGuide(Self.outcome(detail: "noPlaybackCarrier")) == false)
        #expect(VideoGenerationOutcomeText.showsEntryGuide(Self.outcome(detail: nil)) == false)
        #expect(VideoGenerationOutcomeText.showsEntryGuide(Self.outcome(detail: "somethingNewFromServer")) == false)
    }

    /// 中文注释：fwq `APP-MEMO-045`——除首页外，入口页拒因的细分文案只陈述成因，不叫用户换页。
    @Test("非首页入口页拒因的文案不叫用户换页")
    func entryRejectionCopyDoesNotSuggestSwitching() {
        for detail: String in VideoGenerationOutcomeText.entryPageRejectionDetails where detail != "entryPageIsSiteRoot" {
            let text: String = VideoGenerationOutcomeText.reasonDetailText(for: Self.outcome(detail: detail)) ?? ""
            #expect(text.contains("换一个") == false && text.contains("換一個") == false && text.contains("Try a") == false, "\(detail)：\(text)")
        }
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
