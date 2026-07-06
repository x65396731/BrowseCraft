import Foundation
import BrowseCraftCore
import BrowseCraftRulesKit

// 中文注释：BuiltInSource 声明应用随包来源，并为每个来源提供明确 runtime 配置。

/// 中文注释：应用随包提供的内置源。
/// 中文注释：内置源和用户源存放在同一个仓储中，稳定 ID 用于避免每次启动重复插入。
/// 中文注释：这里只负责声明内置来源；具体执行由对应 SourceRuntime 负责。
enum BuiltInSource {
    static let primaryBuiltInID: String = BrowseCraftPrivateRuleCatalog.primaryBuiltInID
    static let primaryBuiltInRuleJSON: String = BrowseCraftPrivateRuleCatalog.primaryBuiltInRuleJSON
    static let solidotRSSID: String = "built-in.rss.solidot"
    static let tiantianVideoID: String = "built-in.video.baixiaotangtop"
    static let genericHTMLVideoID: String = "built-in.video.xvideos"

    static func allBuiltIns(now: Date = Date()) -> [Source] {
        var sources: [Source] = BrowseCraftPrivateRuleCatalog.builtInRules.map { builtInRule in
            return Self.source(from: builtInRule, now: now)
        }
        sources.append(Self.solidotRSS(now: now))
        sources.append(Self.tiantianVideo(now: now))
        sources.append(Self.genericHTMLVideo(now: now))
        return sources
    }

    /// 中文注释：primaryBuiltIn 方法返回默认漫画内置源；内部短期仍由 SiteRule 驱动。
    static func primaryBuiltIn(now: Date = Date()) -> Source {
        return Self.source(
            from: BrowseCraftBuiltInRule(
                id: Self.primaryBuiltInID,
                name: BrowseCraftPrivateRuleCatalog.primaryBuiltInName,
                baseURL: BrowseCraftPrivateRuleCatalog.primaryBuiltInBaseURL,
                ruleJSON: Self.primaryBuiltInRuleJSON
            ),
            now: now
        )
    }

    /// 中文注释：solidotRSS 方法返回公开 RSS feed 内置源。
    static func solidotRSS(now: Date = Date()) -> Source {
        return Source(
            id: Self.solidotRSSID,
            name: "Solidot 奇客",
            baseURL: "https://www.solidot.org",
            type: .rss,
            configuration: .rss(
                RSSSourceConfiguration(
                    definition: RSSSourceDefinition(
                        feedURL: URL(string: "https://www.solidot.org/index.rss")!,
                        requiresAccount: false,
                        refreshPolicy: .manual
                    )
                )
            ),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }


    /// 中文注释：tiantianVideo 方法返回开发验证用 MacCMS 视频源；站点来自 P4.13.1 调研记录。
    static func tiantianVideo(now: Date = Date()) -> Source {
        let entryURL: URL = URL(string: "https://www.baixiaotangtop.com/")!
        let definition: VideoSourceDefinition = VideoSourceDefinition(
            adapter: .macCMS,
            entryURL: entryURL,
            seedURL: nil,
            entryKind: .home,
            routePatterns: .macCMS,
            playbackPolicy: .playPageFirst,
            requiresAccount: false,
            seedVodID: nil,
            seedSourceIndex: nil,
            seedEpisodeIndex: nil,
            seedDetailURL: nil,
            seedPlayURL: nil
        )

        return Source(
            id: Self.tiantianVideoID,
            name: "天天电影（测试）",
            baseURL: entryURL.absoluteString,
            type: .html,
            configuration: .video(
                VideoSourceConfiguration(
                    definition: definition,
                    listTabs: Self.macCMSVideoListTabs(entryURL: entryURL)
                )
            ),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    /// 中文注释：genericHTMLVideo 方法返回开发验证用 GenericHTML 视频源。
    static func genericHTMLVideo(now: Date = Date()) -> Source {
        let entryURL: URL = URL(string: "https://www.xvideos.com/")!
        let definition: VideoSourceDefinition = VideoSourceDefinition(
            adapter: .genericHTML,
            entryURL: entryURL,
            seedURL: nil,
            entryKind: .home,
            routePatterns: nil,
            playbackPolicy: .playPageFirst,
            requiresAccount: false,
            seedVodID: nil,
            seedSourceIndex: nil,
            seedEpisodeIndex: nil,
            seedDetailURL: nil,
            seedPlayURL: nil
        )

        return Source(
            id: Self.genericHTMLVideoID,
            name: "GenericHTML 视频（测试）",
            baseURL: entryURL.absoluteString,
            type: .html,
            configuration: .video(
                VideoSourceConfiguration(
                    definition: definition,
                    listTabs: [
                        Self.genericHTMLVideoHomeTab(entryURL: entryURL)
                    ]
                )
            ),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func macCMSVideoListTabs(entryURL: URL) -> [VideoSourceListTab] {
        return [
            VideoSourceListTab(
                id: "video.home",
                title: "首页",
                url: entryURL.absoluteString,
                itemSelector: ".ewave-vodlist__box",
                titleSelector: ".ewave-vodlist__thumb@title",
                linkSelector: "a[href*=/voddetail/]@href",
                coverSelector: ".ewave-vodlist__thumb@data-original",
                latestTextSelector: ".pic-text.text-right"
            ),
            VideoSourceListTab(
                id: "video.category.1",
                title: "电影",
                url: "/vodtype/1.html",
                itemSelector: ".ewave-vodlist__box",
                titleSelector: ".ewave-vodlist__thumb@title",
                linkSelector: "a[href*=/voddetail/]@href",
                coverSelector: ".ewave-vodlist__thumb@data-original",
                latestTextSelector: ".pic-text.text-right"
            ),
            VideoSourceListTab(
                id: "video.category.2",
                title: "电视剧",
                url: "/vodtype/2.html",
                itemSelector: ".ewave-vodlist__box",
                titleSelector: ".ewave-vodlist__thumb@title",
                linkSelector: "a[href*=/voddetail/]@href",
                coverSelector: ".ewave-vodlist__thumb@data-original",
                latestTextSelector: ".pic-text.text-right"
            ),
            VideoSourceListTab(
                id: "video.category.3",
                title: "综艺",
                url: "/vodtype/3.html",
                itemSelector: ".ewave-vodlist__box",
                titleSelector: ".ewave-vodlist__thumb@title",
                linkSelector: "a[href*=/voddetail/]@href",
                coverSelector: ".ewave-vodlist__thumb@data-original",
                latestTextSelector: ".pic-text.text-right"
            ),
            VideoSourceListTab(
                id: "video.category.4",
                title: "动漫",
                url: "/vodtype/4.html",
                itemSelector: ".ewave-vodlist__box",
                titleSelector: ".ewave-vodlist__thumb@title",
                linkSelector: "a[href*=/voddetail/]@href",
                coverSelector: ".ewave-vodlist__thumb@data-original",
                latestTextSelector: ".pic-text.text-right"
            )
        ]
    }

    private static func genericHTMLVideoHomeTab(entryURL: URL) -> VideoSourceListTab {
        return VideoSourceListTab(
            id: "video.home",
            title: "首页",
            url: entryURL.absoluteString,
            itemSelector: ".frame-block.thumb-block",
            titleSelector: ".thumb-under .title a@title",
            linkSelector: "a[href*=/video]@href",
            coverSelector: "img[data-src], img[src]",
            latestTextSelector: ".duration"
        )
    }

    private static func source(from builtInRule: BrowseCraftBuiltInRule, now: Date) -> Source {
        return Source(
            id: builtInRule.id,
            name: builtInRule.name,
            baseURL: builtInRule.baseURL,
            type: .html,
            rule: Self.rule(from: builtInRule.ruleJSON),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func rule(from ruleJSON: String) -> SiteRule {
        let ruleData: Data = Data(ruleJSON.utf8)

        do {
            return try JSONDecoder().decode(SiteRule.self, from: ruleData)
        } catch {
            // 中文注释：内置 JSON 属于应用包内容，解码失败代表开发期配置错误。
            fatalError("Invalid bundled rule JSON: \(error)")
        }
    }
}
