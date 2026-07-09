import Foundation
import Testing
@testable import BrowseCraft

struct RuleCandidateDraftApplierTests {
    @Test func canApplyMatchesSupportedStageFields() {
        let applier: RuleCandidateDraftApplier = RuleCandidateDraftApplier()

        #expect(applier.canApply(candidate: Self.candidate(field: .item, stage: .list), stage: .list))
        #expect(applier.canApply(candidate: Self.candidate(field: .nextPage, stage: .list), stage: .list))
        #expect(applier.canApply(candidate: Self.candidate(field: .nextPage, stage: .search), stage: .search))
        #expect(applier.canApply(candidate: Self.candidate(field: .chapterTitle, stage: .detail), stage: .detail))
        #expect(applier.canApply(candidate: Self.candidate(field: .image, stage: .reader), stage: .reader))

        #expect(applier.canApply(candidate: Self.candidate(field: .image, stage: .list), stage: .list) == false)
        #expect(applier.canApply(candidate: Self.candidate(field: .title, stage: .search), stage: .search) == false)
        #expect(applier.canApply(candidate: Self.candidate(field: .cover, stage: .detail), stage: .detail) == false)
        #expect(applier.canApply(candidate: Self.candidate(field: .nextPage, stage: .reader), stage: .reader) == false)
        #expect(applier.canApply(candidate: Self.candidate(field: .item, stage: .list), stage: nil) == false)
    }

    @Test func listCandidateUpdatesLegacyListAndTargetRuleSetList() throws {
        var rule: SiteRule = Self.rule()
        let applier: RuleCandidateDraftApplier = RuleCandidateDraftApplier()

        let applied: Bool = applier.apply(
            candidate: Self.candidate(field: .title, stage: .list, selector: "a.name", function: .text),
            stage: .list,
            ruleID: "home-list",
            rule: &rule
        )

        let targetList: ListRule = try #require(rule.ruleSets?.listRules?.first { listRule in
            return listRule.id == "home-list"
        })
        let otherList: ListRule = try #require(rule.ruleSets?.listRules?.first { listRule in
            return listRule.id == "other-list"
        })

        #expect(applied)
        #expect(rule.list.title == "a.name")
        #expect(targetList.title == "a.name")
        #expect(otherList.title == ".other-title")
    }

    @Test func listNextPageManualSeedUpdatesPagePlaceholder() throws {
        var rule: SiteRule = Self.rule()
        let applier: RuleCandidateDraftApplier = RuleCandidateDraftApplier()

        let applied: Bool = applier.apply(
            candidate: Self.candidate(
                field: .nextPage,
                stage: .list,
                selector: "https://example.test/list?page={page}",
                selectorKind: .current,
                function: .raw,
                param: "{page}",
                source: .manualSeed
            ),
            stage: .list,
            ruleID: "home-list",
            rule: &rule
        )

        let targetList: ListRule = try #require(rule.ruleSets?.listRules?.first { listRule in
            return listRule.id == "home-list"
        })

        #expect(applied)
        #expect(rule.list.pagination?.pagePlaceholder == "{page}")
        #expect(targetList.pagination?.pagePlaceholder == "{page}")
        #expect(targetList.pagination?.stopWhenEmpty == true)
    }

    @Test func detailCandidateUpdatesStructuredChapterRuleBeforeLegacyFallback() throws {
        var rule: SiteRule = Self.rule()
        let applier: RuleCandidateDraftApplier = RuleCandidateDraftApplier()

        let applied: Bool = applier.apply(
            candidate: Self.candidate(
                field: .chapterLink,
                stage: .detail,
                selector: "a.chapter",
                function: .url,
                param: "href"
            ),
            stage: .detail,
            ruleID: "detail",
            rule: &rule
        )

        let detailRule: DetailRule = try #require(rule.ruleSets?.detailRule(id: "detail"))

        #expect(applied)
        #expect(detailRule.chapterRule?.url.selector == "a.chapter")
        #expect(detailRule.chapterRule?.url.function == .url)
        #expect(detailRule.chapterRule?.url.param == "href")
        #expect(rule.detail?.chapterLink == ".legacy-link@href")
    }

    @Test func detailCandidateFallsBackToLegacyDetailWhenRuleSetTargetIsMissing() throws {
        var rule: SiteRule = Self.rule()
        let applier: RuleCandidateDraftApplier = RuleCandidateDraftApplier()

        let applied: Bool = applier.apply(
            candidate: Self.candidate(field: .chapterContainer, stage: .detail, selector: "ol.fallback"),
            stage: .detail,
            ruleID: "missing-detail",
            rule: &rule
        )

        #expect(applied)
        #expect(rule.detail?.chapterContainer == "ol.fallback")
        #expect(rule.ruleSets?.detailRule(id: "detail")?.chapterRule?.section?.container.selector == "ul.old")
    }

    @Test func readerCandidateUpdatesV2AndLegacyGalleryFields() throws {
        var rule: SiteRule = Self.rule()
        let applier: RuleCandidateDraftApplier = RuleCandidateDraftApplier()

        let applied: Bool = applier.apply(
            candidate: Self.candidate(
                field: .image,
                stage: .reader,
                selector: "img.page",
                function: .attr,
                param: "data-src"
            ),
            stage: .reader,
            ruleID: "reader",
            rule: &rule
        )

        let galleryRule: GalleryRule = try #require(rule.ruleSets?.galleryRule(id: "reader"))

        #expect(applied)
        #expect(galleryRule.item?.selector == "img.page")
        #expect(galleryRule.item?.function == .raw)
        #expect(galleryRule.image?.selector == "img.page")
        #expect(galleryRule.image?.function == .attr)
        #expect(galleryRule.image?.param == "data-src")
        #expect(galleryRule.imageItem == "img.page")
        #expect(galleryRule.imageUrl == "this@data-src")
        #expect(rule.gallery?.imageItem == ".legacy-page")
    }

    @Test func searchNextPageCandidateUpdatesTargetSearchRule() throws {
        var rule: SiteRule = Self.rule()
        let applier: RuleCandidateDraftApplier = RuleCandidateDraftApplier()

        let applied: Bool = applier.apply(
            candidate: Self.candidate(
                field: .nextPage,
                stage: .search,
                selector: "a.next",
                function: .url,
                param: "href",
                source: .paginationLink
            ),
            stage: .search,
            ruleID: "search",
            rule: &rule
        )

        let searchRule: SearchRule = try #require(rule.ruleSets?.searchRule(id: "search"))

        #expect(applied)
        #expect(searchRule.pagination?.nextPage?.selector == "a.next")
        #expect(searchRule.pagination?.nextPage?.function == .url)
        #expect(searchRule.pagination?.nextPage?.param == "href")
        #expect(searchRule.pagination?.pagePlaceholder == "{page}")
    }

    @Test func unsupportedCandidateDoesNotMutateDraft() {
        var rule: SiteRule = Self.rule()
        let originalRule: SiteRule = rule
        let applier: RuleCandidateDraftApplier = RuleCandidateDraftApplier()

        let applied: Bool = applier.apply(
            candidate: Self.candidate(field: .image, stage: .list, selector: "img.page"),
            stage: .list,
            ruleID: "home-list",
            rule: &rule
        )

        #expect(applied == false)
        #expect(rule == originalRule)
    }

    private static func candidate(
        field: RuleCandidateField,
        stage: RuleAnalysisStage,
        selector: String = ".candidate",
        selectorKind: SelectorKind = .css,
        function: ExtractFunction = .text,
        param: String? = nil,
        source: RuleCandidateSource = .repeatedDOMStructure
    ) -> RuleCandidate {
        return RuleCandidate(
            id: "\(stage.rawValue)-\(field.rawValue)",
            field: field,
            stage: stage,
            selector: selector,
            selectorKind: selectorKind,
            function: function,
            param: param,
            score: RuleCandidateScore(value: 0.9, confidence: .high, reasons: []),
            evidence: RuleCandidateEvidence(
                candidateCount: 1,
                matchedCount: 1,
                sampleValues: [],
                sampleAttributes: [:],
                ancestorHints: []
            ),
            warnings: [],
            source: source
        )
    }

    private static func rule() -> SiteRule {
        return SiteRule(
            version: 2,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: RuleSets(
                seriesRules: nil,
                listRules: [
                    Self.listRule(id: "home-list", title: ".old-title"),
                    Self.listRule(id: "other-list", title: ".other-title")
                ],
                detailRules: [
                    Self.structuredDetailRule()
                ],
                galleryRules: [
                    Self.galleryRule(id: "reader", imageItem: ".old-page", imageUrl: "this@src")
                ],
                searchRules: [
                    Self.searchRule(id: "search")
                ]
            ),
            sharedRequest: nil,
            flags: nil,
            name: "Fixture",
            baseUrl: "https://example.test",
            list: Self.listRule(id: "legacy-list", title: ".legacy-title"),
            listTabs: nil,
            detail: Self.legacyDetailRule(),
            gallery: Self.galleryRule(id: "legacy-gallery", imageItem: ".legacy-page", imageUrl: "this@src"),
            video: nil
        )
    }

    private static func listRule(id: String, title: String) -> ListRule {
        return ListRule(
            id: id,
            url: "https://example.test/list",
            text: nil,
            item: ".item",
            itemRule: nil,
            fields: nil,
            title: title,
            link: "a@href",
            cover: "img@src",
            type: .comic,
            latestText: ".latest",
            pagination: nil,
            ready: nil,
            request: nil,
            js: nil
        )
    }

    private static func structuredDetailRule() -> DetailRule {
        return DetailRule(
            id: "detail",
            fields: nil,
            title: ".detail-title",
            cover: nil,
            mainScope: nil,
            exclude: nil,
            chapterRule: ChapterRule(
                section: SectionRule(
                    id: "chapter-section",
                    title: nil,
                    role: .main,
                    itemLayout: nil,
                    container: Self.extractRule(selector: "ul.old", function: .raw),
                    itemRuleRef: nil,
                    listRuleRef: nil,
                    exclude: nil
                ),
                item: Self.extractRule(selector: "li.old", function: .raw),
                idCode: nil,
                cidCode: nil,
                title: Self.extractRule(selector: ".old-chapter-title", function: .text),
                url: Self.extractRule(selector: ".old-chapter-link", function: .url, param: "href"),
                datetime: nil,
                language: nil,
                index: nil,
                sort: nil,
                mustMatchLatestText: nil
            ),
            chapterContainer: nil,
            chapterItem: nil,
            chapterTitle: nil,
            chapterLink: nil,
            treatDetailURLAsChapter: nil,
            tagRule: nil,
            pictureRule: nil,
            commentRule: nil,
            videoRule: nil,
            ready: nil,
            request: nil,
            js: nil
        )
    }

    private static func legacyDetailRule() -> DetailRule {
        return DetailRule(
            id: "legacy-detail",
            fields: nil,
            title: nil,
            cover: nil,
            mainScope: nil,
            exclude: nil,
            chapterRule: nil,
            chapterContainer: ".legacy-container",
            chapterItem: ".legacy-item",
            chapterTitle: ".legacy-title",
            chapterLink: ".legacy-link@href",
            treatDetailURLAsChapter: nil,
            tagRule: nil,
            pictureRule: nil,
            commentRule: nil,
            videoRule: nil,
            ready: nil,
            request: nil,
            js: nil
        )
    }

    private static func galleryRule(id: String, imageItem: String, imageUrl: String) -> GalleryRule {
        return GalleryRule(
            id: id,
            mainScope: nil,
            item: nil,
            image: nil,
            thumbnail: nil,
            link: nil,
            totalPages: nil,
            secondLevelPageURL: nil,
            variants: nil,
            sourceFiles: nil,
            pagination: nil,
            request: nil,
            js: nil,
            imageItem: imageItem,
            imageUrl: imageUrl,
            comicTitle: nil,
            chapterTitle: nil,
            catalogLink: nil,
            previousLink: nil,
            nextLink: nil
        )
    }

    private static func searchRule(id: String) -> SearchRule {
        return SearchRule(
            id: id,
            keywordEncoding: .urlQueryAllowed,
            url: "https://example.test/search?q={keyword:}&page={page}",
            method: .get,
            request: nil,
            listRuleRef: "home-list",
            item: Self.extractRule(selector: ".search-item", function: .raw),
            fields: ListFields(
                idCode: nil,
                title: Self.extractRule(selector: ".search-title", function: .text),
                cover: nil,
                largeImage: nil,
                video: nil,
                detailURL: Self.extractRule(selector: "a", function: .url, param: "href"),
                latestText: nil,
                description: nil,
                coverWidth: nil,
                coverHeight: nil,
                category: nil,
                author: nil,
                uploader: nil,
                publishedAt: nil,
                datetime: nil,
                rating: nil,
                totalImages: nil,
                language: nil
            ),
            pagination: PaginationRule(
                nextPage: nil,
                pagePlaceholder: "{page}",
                maxPages: nil,
                stopWhenEmpty: true
            )
        )
    }

    private static func extractRule(
        selector: String,
        function: ExtractFunction,
        param: String? = nil
    ) -> ExtractRule {
        return ExtractRule(
            selector: selector,
            selectorKind: .css,
            function: function,
            functions: nil,
            param: param,
            regex: nil,
            replacement: nil,
            fallback: nil
        )
    }
}
