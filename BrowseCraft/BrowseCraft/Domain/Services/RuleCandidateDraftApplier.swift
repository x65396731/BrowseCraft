import Foundation

/// Applies debug rule candidates to an editable rule draft without depending on SwiftUI state.
struct RuleCandidateDraftApplier {
    func canApply(candidate: RuleCandidate, stage: RuleDebugStage?) -> Bool {
        switch stage {
        case .list:
            switch candidate.field {
            case .item, .title, .link, .cover, .latestText, .nextPage:
                return true
            default:
                return false
            }
        case .search:
            return candidate.field == .nextPage
        case .detail:
            switch candidate.field {
            case .chapterContainer, .chapterItem, .chapterTitle, .chapterLink:
                return true
            default:
                return false
            }
        case .reader:
            return candidate.field == .image
        case nil:
            return false
        }
    }

    func apply(candidate: RuleCandidate, stage: RuleDebugStage?, ruleID: String?, rule: inout SiteRule) -> Bool {
        switch stage {
        case .list:
            return self.applyListCandidate(candidate, ruleID: ruleID, rule: &rule)
        case .search:
            return self.applySearchCandidate(candidate, ruleID: ruleID, rule: &rule)
        case .detail:
            return self.applyDetailCandidate(candidate, ruleID: ruleID, rule: &rule)
        case .reader:
            return self.applyReaderCandidate(candidate, ruleID: ruleID, rule: &rule)
        case nil:
            return false
        }
    }

    private func applyListCandidate(_ candidate: RuleCandidate, ruleID: String?, rule: inout SiteRule) -> Bool {
        var didApply: Bool = self.applyListCandidate(candidate, listRule: &rule.list)

        guard var ruleSets: RuleSets = rule.ruleSets,
              var listRules: [ListRule] = ruleSets.listRules else {
            return didApply
        }

        let targetIndex: Array<ListRule>.Index?
        if let ruleID: String = ruleID {
            targetIndex = listRules.firstIndex { listRule in
                return listRule.id == ruleID
            }
        } else {
            targetIndex = listRules.indices.first
        }

        if let targetIndex: Array<ListRule>.Index = targetIndex {
            didApply = self.applyListCandidate(candidate, listRule: &listRules[targetIndex]) || didApply
            ruleSets.listRules = listRules
            rule.ruleSets = ruleSets
        }

        return didApply
    }

    private func applyListCandidate(_ candidate: RuleCandidate, listRule: inout ListRule) -> Bool {
        switch candidate.field {
        case .item:
            listRule.item = candidate.selector
        case .title:
            listRule.title = self.legacyRuleExpression(candidate)
        case .link:
            listRule.link = self.legacyRuleExpression(candidate)
        case .cover:
            listRule.cover = self.legacyRuleExpression(candidate)
        case .latestText:
            listRule.latestText = self.legacyRuleExpression(candidate)
        case .nextPage:
            listRule.pagination = self.updatedPagination(candidate, existing: listRule.pagination)
        default:
            return false
        }

        return true
    }

    private func applyDetailCandidate(_ candidate: RuleCandidate, ruleID: String?, rule: inout SiteRule) -> Bool {
        if var ruleSets: RuleSets = rule.ruleSets,
           var detailRules: [DetailRule] = ruleSets.detailRules {
            let targetIndex: Array<DetailRule>.Index?
            if let ruleID: String = ruleID {
                targetIndex = detailRules.firstIndex { detailRule in
                    return detailRule.id == ruleID
                }
            } else {
                targetIndex = detailRules.indices.first
            }

            if let targetIndex: Array<DetailRule>.Index = targetIndex,
               self.applyDetailCandidate(candidate, detailRule: &detailRules[targetIndex]) {
                ruleSets.detailRules = detailRules
                rule.ruleSets = ruleSets
                return true
            }
        }

        guard var detailRule: DetailRule = rule.detail,
              self.applyDetailCandidate(candidate, detailRule: &detailRule) else {
            return false
        }

        rule.detail = detailRule
        return true
    }

    private func applyDetailCandidate(_ candidate: RuleCandidate, detailRule: inout DetailRule) -> Bool {
        if var chapterRule: ChapterRule = detailRule.chapterRule {
            guard self.applyDetailCandidate(candidate, chapterRule: &chapterRule) else {
                return false
            }

            detailRule.chapterRule = chapterRule
            return true
        }

        switch candidate.field {
        case .chapterContainer:
            detailRule.chapterContainer = candidate.selector
        case .chapterItem:
            detailRule.chapterItem = candidate.selector
        case .chapterTitle:
            detailRule.chapterTitle = self.legacyRuleExpression(candidate)
        case .chapterLink:
            detailRule.chapterLink = self.legacyRuleExpression(candidate)
        default:
            return false
        }

        return true
    }

    private func applyDetailCandidate(_ candidate: RuleCandidate, chapterRule: inout ChapterRule) -> Bool {
        switch candidate.field {
        case .chapterContainer:
            if var section: SectionRule = chapterRule.section {
                section.container = self.extractRule(candidate)
                chapterRule.section = section
            } else {
                chapterRule.section = SectionRule(
                    id: nil,
                    title: nil,
                    role: nil,
                    itemLayout: nil,
                    container: self.extractRule(candidate),
                    itemRuleRef: nil,
                    listRuleRef: nil,
                    exclude: nil
                )
            }
        case .chapterItem:
            chapterRule.item = self.extractRule(candidate)
        case .chapterTitle:
            chapterRule.title = self.extractRule(candidate)
        case .chapterLink:
            chapterRule.url = self.extractRule(candidate)
        default:
            return false
        }

        return true
    }

    private func applyReaderCandidate(_ candidate: RuleCandidate, ruleID: String?, rule: inout SiteRule) -> Bool {
        if var ruleSets: RuleSets = rule.ruleSets,
           var galleryRules: [GalleryRule] = ruleSets.galleryRules {
            let targetIndex: Array<GalleryRule>.Index?
            if let ruleID: String = ruleID {
                targetIndex = galleryRules.firstIndex { galleryRule in
                    return galleryRule.id == ruleID
                }
            } else {
                targetIndex = galleryRules.indices.first
            }

            if let targetIndex: Array<GalleryRule>.Index = targetIndex,
               self.applyReaderCandidate(candidate, galleryRule: &galleryRules[targetIndex]) {
                ruleSets.galleryRules = galleryRules
                rule.ruleSets = ruleSets
                return true
            }
        }

        guard var galleryRule: GalleryRule = rule.gallery,
              self.applyReaderCandidate(candidate, galleryRule: &galleryRule) else {
            return false
        }

        rule.gallery = galleryRule
        return true
    }

    private func applyReaderCandidate(_ candidate: RuleCandidate, galleryRule: inout GalleryRule) -> Bool {
        guard candidate.field == .image else {
            return false
        }

        galleryRule.item = self.nodeExtractRule(candidate)
        galleryRule.image = self.extractRule(candidate)
        galleryRule.imageItem = candidate.selector
        galleryRule.imageUrl = self.legacyCurrentRuleExpression(candidate)
        return true
    }

    private func applySearchCandidate(_ candidate: RuleCandidate, ruleID: String?, rule: inout SiteRule) -> Bool {
        guard candidate.field == .nextPage,
              var ruleSets: RuleSets = rule.ruleSets,
              var searchRules: [SearchRule] = ruleSets.searchRules else {
            return false
        }

        let targetIndex: Array<SearchRule>.Index?
        if let ruleID: String = ruleID {
            targetIndex = searchRules.firstIndex { searchRule in
                return searchRule.id == ruleID
            }
        } else {
            targetIndex = searchRules.indices.first
        }

        guard let targetIndex: Array<SearchRule>.Index = targetIndex else {
            return false
        }

        searchRules[targetIndex].pagination = self.updatedPagination(
            candidate,
            existing: searchRules[targetIndex].pagination
        )
        ruleSets.searchRules = searchRules
        rule.ruleSets = ruleSets
        return true
    }

    private func updatedPagination(_ candidate: RuleCandidate, existing: PaginationRule?) -> PaginationRule {
        var pagination: PaginationRule = existing ?? PaginationRule(
            nextPage: nil,
            pagePlaceholder: nil,
            maxPages: nil,
            stopWhenEmpty: true
        )

        if candidate.source == .paginationLink {
            pagination.nextPage = self.extractRule(candidate)
        } else if candidate.source == .manualSeed {
            pagination.pagePlaceholder = candidate.param
        }

        return pagination
    }

    private func nodeExtractRule(_ candidate: RuleCandidate) -> ExtractRule {
        return ExtractRule(
            selector: candidate.selector,
            selectorKind: candidate.selectorKind,
            function: .raw,
            functions: nil,
            param: nil,
            regex: nil,
            replacement: nil,
            fallback: nil
        )
    }

    private func extractRule(_ candidate: RuleCandidate) -> ExtractRule {
        return ExtractRule(
            selector: candidate.selector,
            selectorKind: candidate.selectorKind,
            function: candidate.function,
            functions: nil,
            param: candidate.param,
            regex: nil,
            replacement: nil,
            fallback: nil
        )
    }

    private func legacyRuleExpression(_ candidate: RuleCandidate) -> String {
        if let param: String = candidate.param,
           param.contains("|") == false {
            return "\(candidate.selector)@\(param)"
        }

        return candidate.selector
    }

    private func legacyCurrentRuleExpression(_ candidate: RuleCandidate) -> String {
        if let param: String = candidate.param,
           param.isEmpty == false {
            return "this@\(param)"
        }

        return "this"
    }
}
