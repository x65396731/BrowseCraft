import Foundation

// 中文注释：ResolvedSiteRule 是 SiteRule 的运行时解析视图，用于集中处理 V2 pages 与 ruleSets 的引用绑定。

/// 中文注释：运行时规则图使用引用类型承载 raw rule，entry 只保存轻量索引，避免复制大型 rule 值。
final class ResolvedSiteRule {
    let raw: SiteRule
    private(set) var detailEntry: ResolvedDetailEntry?
    private(set) var galleryEntry: ResolvedGalleryEntry?

    init(raw: SiteRule) {
        self.raw = raw
        self.detailEntry = nil
        self.galleryEntry = nil
        withUnsafePointer(to: self.raw) { rawPointer in
            self.detailEntry = Self.resolveDetailEntry(raw: rawPointer)
            self.galleryEntry = Self.resolveGalleryEntry(raw: rawPointer)
        }
    }

    var primaryDetailRule: DetailRule? {
        guard let detailEntry: ResolvedDetailEntry = self.detailEntry else {
            return nil
        }

        return self.detailRule(for: detailEntry)
    }

    var primaryGalleryRule: GalleryRule? {
        guard let galleryEntry: ResolvedGalleryEntry = self.galleryEntry else {
            return nil
        }

        return self.galleryRule(for: galleryEntry)
    }

    var primaryDetailRequest: RequestConfig? {
        return self.detailEntry?.effectiveRequest
    }

    var primaryGalleryRequest: RequestConfig? {
        return self.galleryEntry?.effectiveRequest
    }

    var primaryDetailContext: ResolvedDetailContext? {
        guard let detailEntry: ResolvedDetailEntry = self.detailEntry,
              self.detailRule(for: detailEntry) != nil else {
            return nil
        }

        return ResolvedDetailContext(entry: detailEntry)
    }

    var primaryReaderContext: ResolvedReaderContext? {
        guard let galleryEntry: ResolvedGalleryEntry = self.galleryEntry,
              self.galleryRule(for: galleryEntry) != nil else {
            return nil
        }

        return ResolvedReaderContext(entry: galleryEntry)
    }

    var treatsDetailURLAsChapter: Bool {
        return self.primaryDetailRule?.treatDetailURLAsChapter == true
    }

    func detailRule(for context: ResolvedDetailContext) -> DetailRule? {
        return self.detailRule(for: context.entry)
    }

    func galleryRule(for context: ResolvedReaderContext) -> GalleryRule? {
        return self.galleryRule(for: context.entry)
    }

    private func detailRule(for entry: ResolvedDetailEntry) -> DetailRule? {
        if entry.usesLegacyRule {
            return self.raw.detail
        }

        guard let ruleIndex: Int = entry.ruleIndex else {
            return nil
        }

        return self.raw.ruleSets?.detailRules?[ruleIndex]
    }

    private func galleryRule(for entry: ResolvedGalleryEntry) -> GalleryRule? {
        if entry.usesLegacyRule {
            return self.raw.gallery
        }

        guard let ruleIndex: Int = entry.ruleIndex else {
            return nil
        }

        return self.raw.ruleSets?.galleryRules?[ruleIndex]
    }

    private static func resolveDetailEntry(raw: UnsafePointer<SiteRule>) -> ResolvedDetailEntry? {
        if let pages: [PageRule] = raw.pointee.pages,
           let detailRules: [DetailRule] = raw.pointee.ruleSets?.detailRules {
            for pageIndex: Array<PageRule>.Index in pages.indices {
                guard pages[pageIndex].isDetailEntryPage,
                      let normalizedRuleID: String = Self.normalizedRuleID(pages[pageIndex].ruleRefs?.detail) else {
                    continue
                }

                var matchedRuleIndex: Array<DetailRule>.Index?
                for ruleIndex: Array<DetailRule>.Index in detailRules.indices {
                    if detailRules[ruleIndex].id == normalizedRuleID {
                        matchedRuleIndex = ruleIndex
                        break
                    }
                }

                guard let ruleIndex: Array<DetailRule>.Index = matchedRuleIndex else {
                    continue
                }

                return ResolvedDetailEntry(
                    pageIndex: pageIndex,
                    ruleIndex: ruleIndex,
                    pageID: pages[pageIndex].id,
                    ruleID: detailRules[ruleIndex].id,
                    pageRequest: pages[pageIndex].request,
                    effectiveRequest: Self.effectiveRequest(
                        sharedRequest: raw.pointee.sharedRequest,
                        pageRequest: pages[pageIndex].request,
                        ruleRequest: detailRules[ruleIndex].request
                    ),
                    usesLegacyRule: false
                )
            }
        }

        guard raw.pointee.detail != nil else {
            return nil
        }

        return ResolvedDetailEntry(
            pageIndex: nil,
            ruleIndex: nil,
            pageID: nil,
            ruleID: raw.pointee.detail?.id,
            pageRequest: nil,
            effectiveRequest: Self.effectiveRequest(
                sharedRequest: raw.pointee.sharedRequest,
                pageRequest: nil,
                ruleRequest: raw.pointee.detail?.request
            ),
            usesLegacyRule: true
        )
    }

    private static func resolveGalleryEntry(raw: UnsafePointer<SiteRule>) -> ResolvedGalleryEntry? {
        if let pages: [PageRule] = raw.pointee.pages,
           let galleryRules: [GalleryRule] = raw.pointee.ruleSets?.galleryRules {
            for pageIndex: Array<PageRule>.Index in pages.indices {
                guard pages[pageIndex].isGalleryEntryPage,
                      let normalizedRuleID: String = Self.normalizedRuleID(pages[pageIndex].ruleRefs?.gallery) else {
                    continue
                }

                var matchedRuleIndex: Array<GalleryRule>.Index?
                for ruleIndex: Array<GalleryRule>.Index in galleryRules.indices {
                    if galleryRules[ruleIndex].id == normalizedRuleID {
                        matchedRuleIndex = ruleIndex
                        break
                    }
                }

                guard let ruleIndex: Array<GalleryRule>.Index = matchedRuleIndex else {
                    continue
                }

                return ResolvedGalleryEntry(
                    pageIndex: pageIndex,
                    ruleIndex: ruleIndex,
                    pageID: pages[pageIndex].id,
                    ruleID: galleryRules[ruleIndex].id,
                    pageRequest: pages[pageIndex].request,
                    effectiveRequest: Self.effectiveRequest(
                        sharedRequest: raw.pointee.sharedRequest,
                        pageRequest: pages[pageIndex].request,
                        ruleRequest: galleryRules[ruleIndex].request
                    ),
                    usesLegacyRule: false
                )
            }
        }

        guard raw.pointee.gallery != nil else {
            return nil
        }

        return ResolvedGalleryEntry(
            pageIndex: nil,
            ruleIndex: nil,
            pageID: nil,
            ruleID: raw.pointee.gallery?.id,
            pageRequest: nil,
            effectiveRequest: Self.effectiveRequest(
                sharedRequest: raw.pointee.sharedRequest,
                pageRequest: nil,
                ruleRequest: raw.pointee.gallery?.request
            ),
            usesLegacyRule: true
        )
    }

    private static func normalizedRuleID(_ id: String?) -> String? {
        guard let normalizedID: String = id?.trimmingCharacters(in: .whitespacesAndNewlines),
              normalizedID.isEmpty == false else {
            return nil
        }

        return normalizedID
    }

    /// 中文注释：P1-4.1 的选择策略保持 Rule > Page > Site，不在 resolved graph 中做深度合并。
    private static func effectiveRequest(
        sharedRequest: RequestConfig?,
        pageRequest: RequestConfig?,
        ruleRequest: RequestConfig?
    ) -> RequestConfig? {
        return ruleRequest ?? pageRequest ?? sharedRequest
    }
}

/// 中文注释：详情入口只保存索引和请求快照；实际 DetailRule 由 ResolvedSiteRule 按索引读取。
struct ResolvedDetailEntry: Hashable {
    let pageIndex: Int?
    let ruleIndex: Int?
    let pageID: String?
    let ruleID: String?
    let pageRequest: RequestConfig?
    let effectiveRequest: RequestConfig?
    let usesLegacyRule: Bool
}

/// 中文注释：阅读入口只保存索引和请求快照；实际 GalleryRule 由 ResolvedSiteRule 按索引读取。
struct ResolvedGalleryEntry: Hashable {
    let pageIndex: Int?
    let ruleIndex: Int?
    let pageID: String?
    let ruleID: String?
    let pageRequest: RequestConfig?
    let effectiveRequest: RequestConfig?
    let usesLegacyRule: Bool
}

/// 中文注释：Detail Debug 只持有 resolved entry，不复制 DetailRule；实际规则由 ResolvedSiteRule 按索引读取。
struct ResolvedDetailContext: Hashable {
    let entry: ResolvedDetailEntry

    var pageID: String? {
        return self.entry.pageID
    }

    var ruleID: String? {
        return self.entry.ruleID
    }

    var request: RequestConfig? {
        return self.entry.effectiveRequest
    }

    var usesLegacyRule: Bool {
        return self.entry.usesLegacyRule
    }
}

/// 中文注释：Reader Debug 只持有 resolved entry，不复制 GalleryRule；实际规则由 ResolvedSiteRule 按索引读取。
struct ResolvedReaderContext: Hashable {
    let entry: ResolvedGalleryEntry

    var pageID: String? {
        return self.entry.pageID
    }

    var ruleID: String? {
        return self.entry.ruleID
    }

    var request: RequestConfig? {
        return self.entry.effectiveRequest
    }

    var usesLegacyRule: Bool {
        return self.entry.usesLegacyRule
    }
}

/// 中文注释：RuleResolver 负责创建运行时 graph，避免业务层反复拼接 page + rule tuple。
struct RuleResolver {
    func resolve(_ rule: SiteRule) -> ResolvedSiteRule {
        return ResolvedSiteRule(raw: rule)
    }
}
