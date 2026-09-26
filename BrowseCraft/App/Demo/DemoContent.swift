#if DEBUG
import BrowseCraftDomain
import Foundation

/// 中文注释：演示模式的全部自造内容——三个示例站、十二部作品、详情简介、剧集 / 章节与一章正文。
/// 片名与封面一一对应（第 N 部作品用 cover-NN.png），都是原创，不对应任何真实作品或站点；
/// 站点域名只用 example.com，这是 RFC 2606 专门留给示例的保留域名。
/// 文案按系统首选语言取繁中 / 简中 / 英文三种，商城三套语言的截图都从这里出。
enum DemoLanguage: Sendable {
    case traditionalChinese
    case simplifiedChinese
    case english

    static let current: DemoLanguage = {
        let preferred: String = Locale.preferredLanguages.first ?? ""
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") {
            return .traditionalChinese
        }
        if preferred.hasPrefix("zh") {
            return .simplifiedChinese
        }
        return .english
    }()
}

struct DemoText: Sendable {
    let hant: String
    let hans: String
    let en: String

    var value: String {
        switch DemoLanguage.current {
        case .traditionalChinese:
            return self.hant
        case .simplifiedChinese:
            return self.hans
        case .english:
            return self.en
        }
    }

    func formatted(_ number: Int) -> String {
        return String(format: self.value, number)
    }
}

enum DemoKind: Sendable {
    case video
    case comic
    case book
}

struct DemoWork: Sendable {
    let number: Int
    let kind: DemoKind
    let slug: String
    let title: DemoText
    let synopsis: DemoText?

    var coverURL: URL? {
        return DemoMode.coverURL(number: self.number)
    }
}

struct DemoSite: Sendable {
    let id: String
    let kind: DemoKind
    let host: String
    let name: DemoText

    var baseURL: String {
        return "https://\(self.host)/"
    }

    func detailURL(for work: DemoWork) -> URL {
        return URL(string: "https://\(self.host)/works/\(work.slug)/")!
    }
}

enum DemoContent {
    static let videoSite: DemoSite = DemoSite(
        id: "built-in.demo-video",
        kind: .video,
        host: "video.example.com",
        name: DemoText(hant: "示例影視站", hans: "示例影视站", en: "Demo Video Site")
    )
    static let comicSite: DemoSite = DemoSite(
        id: "built-in.demo-comic",
        kind: .comic,
        host: "comic.example.com",
        name: DemoText(hant: "示例漫畫站", hans: "示例漫画站", en: "Demo Comic Site")
    )
    static let bookSite: DemoSite = DemoSite(
        id: "built-in.demo-book",
        kind: .book,
        host: "books.example.com",
        name: DemoText(hant: "示例書站", hans: "示例书站", en: "Demo Book Site")
    )
    /// 中文注释：id 用 `built-in.` 前缀——内置来源不占名额、不会被名额锁住（`Source.isBuiltIn`），
    /// 未登录时会话启动会把名额重置回 1，演示的三个站因此不能走普通来源。
    static let sites: [DemoSite] = [videoSite, comicSite, bookSite]

    static let works: [DemoWork] = [
        DemoWork(
            number: 1, kind: .video, slug: "starport-night-voyage",
            title: DemoText(hant: "星港夜航", hans: "星港夜航", en: "Starport Night Voyage"),
            synopsis: DemoText(
                hant: "末班貨運艦「晨星號」在星港停靠的最後一夜，年輕的領航員發現艙底藏著一個不該存在的乘客。天亮之前，她必須決定要不要讓這艘船照常起航。",
                hans: "末班货运舰「晨星号」在星港停靠的最后一夜，年轻的领航员发现舱底藏着一个不该存在的乘客。天亮之前，她必须决定要不要让这艘船照常起航。",
                en: "On the freighter Morningstar's last night in port, a young navigator finds a passenger hidden in the hold who shouldn't exist. Before dawn, she has to decide whether the ship still sails."
            )
        ),
        DemoWork(
            number: 2, kind: .video, slug: "changan-chronicles",
            title: DemoText(hant: "長安異聞錄", hans: "长安异闻录", en: "Chang'an Chronicles"),
            synopsis: nil
        ),
        DemoWork(
            number: 3, kind: .video, slug: "letters-from-fog-city",
            title: DemoText(hant: "霧城來信", hans: "雾城来信", en: "Letters from Fog City"),
            synopsis: nil
        ),
        DemoWork(
            number: 4, kind: .video, slug: "summer-corner-store",
            title: DemoText(hant: "夏日便利店", hans: "夏日便利店", en: "Summer Corner Store"),
            synopsis: nil
        ),
        DemoWork(
            number: 5, kind: .comic, slug: "burn-on-squad-seven",
            title: DemoText(hant: "燃燒吧！第七中隊", hans: "燃烧吧！第七中队", en: "Burn On, Squad Seven"),
            synopsis: nil
        ),
        DemoWork(
            number: 6, kind: .comic, slug: "after-school-astronomy-club",
            title: DemoText(hant: "放學後的天文部", hans: "放学后的天文部", en: "After-School Astronomy Club"),
            synopsis: DemoText(
                hant: "只剩兩個社員的天文部，靠一台舊望遠鏡撐過每個晴朗的夜晚。直到某天，鏡頭裡出現了一顆星圖上沒有的星星。",
                hans: "只剩两个社员的天文部，靠一台旧望远镜撑过每个晴朗的夜晚。直到某天，镜头里出现了一颗星图上没有的星星。",
                en: "Down to two members, the astronomy club gets by with one old telescope and every clear night. Then a star that isn't on any chart shows up in the eyepiece."
            )
        ),
        DemoWork(
            number: 7, kind: .comic, slug: "dragonbone-and-compass",
            title: DemoText(hant: "龍骨與羅盤", hans: "龙骨与罗盘", en: "Dragonbone & Compass"),
            synopsis: nil
        ),
        DemoWork(
            number: 8, kind: .comic, slug: "the-cats-midnight-kitchen",
            title: DemoText(hant: "貓咪的深夜廚房", hans: "猫咪的深夜厨房", en: "The Cat's Midnight Kitchen"),
            synopsis: nil
        ),
        DemoWork(
            number: 9, kind: .book, slug: "sword-beyond-nine-skies",
            title: DemoText(hant: "九霄問劍", hans: "九霄问剑", en: "Sword Beyond the Nine Skies"),
            synopsis: DemoText(
                hant: "山門外的雲海三十年不散，少年劍修要在雲散之前，找到師父留下的最後一式劍招。",
                hans: "山门外的云海三十年不散，少年剑修要在云散之前，找到师父留下的最后一式剑招。",
                en: "The sea of clouds outside the mountain gate hasn't cleared in thirty years. A young swordsman must find his master's final technique before it does."
            )
        ),
        DemoWork(
            number: 10, kind: .book, slug: "the-thirteenth-floor",
            title: DemoText(hant: "寫字樓第十三層", hans: "写字楼第十三层", en: "The Thirteenth Floor"),
            synopsis: nil
        ),
        DemoWork(
            number: 11, kind: .book, slug: "silent-testimony",
            title: DemoText(hant: "無聲證詞", hans: "无声证词", en: "Silent Testimony"),
            synopsis: nil
        ),
        DemoWork(
            number: 12, kind: .book, slug: "song-of-the-voyager",
            title: DemoText(hant: "遠航者之歌", hans: "远航者之歌", en: "Song of the Voyager"),
            synopsis: nil
        )
    ]

    static func site(id: String) -> DemoSite? {
        return self.sites.first { site in
            return site.id == id
        }
    }

    /// 中文注释：每个示例站都列出全部十二部，本站那一类排在最前面，列表网格才铺得满。
    static func listWorks(for site: DemoSite) -> [DemoWork] {
        let own: [DemoWork] = self.works.filter { work in work.kind == site.kind }
        let others: [DemoWork] = self.works.filter { work in work.kind != site.kind }
        return own + others
    }

    static func work(site: DemoSite, detailURL: URL) -> DemoWork? {
        return self.works.first { work in
            return site.detailURL(for: work) == detailURL
        }
    }

    static func latestText(for kind: DemoKind) -> String {
        switch kind {
        case .video:
            return DemoText(hant: "更新至第 12 集", hans: "更新至第 12 集", en: "Up to Ep. 12").value
        case .comic:
            return DemoText(hant: "連載至第 48 話", hans: "连载至第 48 话", en: "Up to Ch. 48").value
        case .book:
            return DemoText(hant: "已完結 · 120 章", hans: "已完结 · 120 章", en: "Completed · 120 ch.").value
        }
    }

    static let defaultSynopsis: DemoText = DemoText(
        hant: "這是一部演示用的原創作品，簡介、封面與章節都是為截圖準備的示例內容。",
        hans: "这是一部演示用的原创作品，简介、封面与章节都是为截图准备的示例内容。",
        en: "An original demo title. Its synopsis, cover and chapters are sample content made for screenshots."
    )

    static let episodeTitle: DemoText = DemoText(hant: "第 %d 集", hans: "第 %d 集", en: "Episode %d")
    static let comicChapterTitle: DemoText = DemoText(hant: "第 %d 話", hans: "第 %d 话", en: "Chapter %d")
    static let bookChapterTitle: DemoText = DemoText(hant: "第 %d 章", hans: "第 %d 章", en: "Chapter %d")

    static let videoAttributes: [(label: DemoText, value: DemoText)] = [
        (DemoText(hant: "類型", hans: "类型", en: "Genre"), DemoText(hant: "科幻 / 冒險", hans: "科幻 / 冒险", en: "Sci-fi / Adventure")),
        (DemoText(hant: "年份", hans: "年份", en: "Year"), DemoText(hant: "2026", hans: "2026", en: "2026")),
        (DemoText(hant: "集數", hans: "集数", en: "Episodes"), DemoText(hant: "全 12 集", hans: "全 12 集", en: "12 episodes"))
    ]

    /// 中文注释：书籍阅读器截图用的一章正文；每本演示书的每一章都回这一份。
    static let bookParagraphs: [DemoText] = [
        DemoText(
            hant: "山門外的雲海，已經三十年沒有散過了。",
            hans: "山门外的云海，已经三十年没有散过了。",
            en: "The sea of clouds outside the mountain gate had not cleared in thirty years."
        ),
        DemoText(
            hant: "沈青站在斷崖邊，衣角被風吹得獵獵作響。腳下是看不見底的白，遠處偶爾有一兩座山峰探出頭來，像沉在海裡的島。",
            hans: "沈青站在断崖边，衣角被风吹得猎猎作响。脚下是看不见底的白，远处偶尔有一两座山峰探出头来，像沉在海里的岛。",
            en: "Shen Qing stood at the edge of the cliff, his robe snapping in the wind. Below him was bottomless white; now and then a peak rose out of it in the distance, like an island in a drowned sea."
        ),
        DemoText(
            hant: "師父說過，雲散的那一天，就是那一式劍招現世的時候。可師父沒說，那一天究竟還要等多久。",
            hans: "师父说过，云散的那一天，就是那一式剑招现世的时候。可师父没说，那一天究竟还要等多久。",
            en: "His master had said the technique would reveal itself on the day the clouds lifted. He had never said how long that day would take to come."
        ),
        DemoText(
            hant: "他低頭看了看手裡的劍。劍身很舊，刃口卻亮得像剛磨過，映出一線天光。",
            hans: "他低头看了看手里的剑。剑身很旧，刃口却亮得像刚磨过，映出一线天光。",
            en: "He looked down at the sword in his hand. The blade was old, but its edge shone as if freshly honed, catching a thin line of sky."
        ),
        DemoText(
            hant: "「再等下去，雲不散，人倒先散了。」身後有人笑著說。",
            hans: "「再等下去，云不散，人倒先散了。」身后有人笑着说。",
            en: "\"Wait much longer and the clouds won't lift — you'll just drift away yourself,\" someone behind him said with a laugh."
        ),
        DemoText(
            hant: "沈青沒有回頭。他知道來的是誰，也知道對方說得沒錯。只是這一次，他想試試看，不等雲散，自己走進雲裡去。",
            hans: "沈青没有回头。他知道来的是谁，也知道对方说得没错。只是这一次，他想试试看，不等云散，自己走进云里去。",
            en: "Shen Qing didn't turn around. He knew who it was, and he knew they were right. But this time he wanted to try something else: not to wait for the clouds, but to walk into them."
        ),
        DemoText(
            hant: "風忽然停了。雲海像被誰輕輕撥開一道縫，縫的那頭，有一座他從沒見過的山。",
            hans: "风忽然停了。云海像被谁轻轻拨开一道缝，缝的那头，有一座他从没见过的山。",
            en: "The wind stopped. The clouds parted as if brushed aside by an unseen hand, and through the gap stood a mountain he had never seen before."
        )
    ]

    /// 中文注释：演示来源带的规则只用来让 App 认出 kind 并推出列表页（单页 → 不显示标签栏）；
    /// 真正的列表、详情、正文由 `DemoSourceRuntimeResolver` 返回，选择器永远不会被执行。
    static func catalogSource(for site: DemoSite) -> CatalogSource {
        let name: String = site.name.value
        let allTitle: String = DemoText(hant: "全部", hans: "全部", en: "All").value
        switch site.kind {
        case .comic:
            return CatalogSource(
                id: site.id,
                name: name,
                baseURL: site.baseURL,
                kind: .comic,
                ruleJSON: """
                {
                  "version": 1,
                  "name": "\(name)",
                  "baseUrl": "\(site.baseURL)",
                  "list": {
                    "id": "all",
                    "url": "\(site.baseURL)works/",
                    "item": ".work-card",
                    "title": "this",
                    "link": "this@href",
                    "cover": "img@src",
                    "type": "comic"
                  },
                  "detail": {
                    "id": "detail",
                    "title": "h1",
                    "cover": "img@src",
                    "chapterContainer": "body",
                    "chapterItem": "a.chapter",
                    "chapterTitle": "this",
                    "chapterLink": "this@href"
                  },
                  "gallery": {
                    "id": "reader",
                    "imageItem": "img",
                    "imageUrl": "this@src"
                  }
                }
                """
            )
        case .video:
            return CatalogSource(
                id: site.id,
                name: name,
                baseURL: site.baseURL,
                kind: .video,
                ruleJSON: """
                {
                  "version": 2,
                  "name": "\(name)",
                  "baseUrl": "\(site.baseURL)",
                  "site": { "name": "\(name)", "domain": "\(site.host)", "baseURL": "\(site.baseURL)" },
                  "pages": [
                    { "id": "all", "title": "\(allTitle)", "type": "list", "url": "/works/", "ruleRefs": { "list": "video-list" } }
                  ],
                  "ruleSets": {
                    "listRules": [
                      {
                        "id": "video-list",
                        "item": { "selector": ".work-card", "selectorKind": "css", "function": "raw" },
                        "fields": {
                          "title": { "selectorKind": "current", "function": "text" },
                          "detailURL": { "selector": "a[href]", "selectorKind": "css", "function": "url", "param": "href" }
                        }
                      }
                    ]
                  }
                }
                """
            )
        case .book:
            return CatalogSource(
                id: site.id,
                name: name,
                baseURL: site.baseURL,
                kind: .book,
                ruleJSON: """
                {
                  "version": 2,
                  "name": "\(name)",
                  "baseUrl": "\(site.baseURL)",
                  "site": { "name": "\(name)", "domain": "\(site.host)", "baseURL": "\(site.baseURL)" },
                  "pages": [
                    {
                      "id": "all", "title": "\(allTitle)", "type": "list", "url": "\(site.baseURL)works/",
                      "ruleRefs": { "list": "book-list", "detail": "book-detail", "reader": "book-reader" }
                    }
                  ],
                  "ruleSets": {
                    "listRules": [
                      {
                        "id": "book-list",
                        "url": "\(site.baseURL)works/",
                        "type": "book",
                        "itemRule": { "function": "raw", "selector": ".work-card", "selectorKind": "css" },
                        "fields": {
                          "title": { "function": "text", "selector": "h3", "selectorKind": "css" },
                          "detailURL": { "function": "url", "param": "href", "selector": "a[href]", "selectorKind": "css" },
                          "cover": { "function": "url", "param": "src", "selector": "img[src]", "selectorKind": "css" }
                        }
                      }
                    ],
                    "detailRules": [
                      {
                        "id": "book-detail",
                        "fields": { "title": { "function": "text", "selector": "h1", "selectorKind": "css" } },
                        "chapterRule": {
                          "item": { "function": "raw", "selector": "a.chapter[href]", "selectorKind": "css" },
                          "title": { "function": "text", "selectorKind": "current" },
                          "readerURL": { "function": "url", "param": "href", "selectorKind": "current" }
                        }
                      }
                    ],
                    "readerRules": [
                      {
                        "id": "book-reader",
                        "variant": "text-dom",
                        "contentType": "text",
                        "content": {
                          "container": { "function": "raw", "selectorKind": "css", "selector": "article" },
                          "segmentation": "lineBreaks"
                        }
                      }
                    ]
                  }
                }
                """
            )
        }
    }
}
#endif
