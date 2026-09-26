import Foundation

/// 设备/用户实际地区推出的 `Accept-Language`（`BC-ACQ-062`）。
///
/// 中文注释：这是**地区取值的单一定义点**。三处读同一个值，三端因此到达同一个页面：
///
/// 1. 预检取页（`PreflightHTTPPageLoader` / `PreflightRenderedPageLoader` 经
///    `SafariRequestHeaderProvider`）；
/// 2. 提交生成任务时随请求发给服务端（`PortalRuleGenerationRequest.acceptLanguage`），
///    引擎拿它作语言头候选表的第一项并写进规则；
/// 3. 运行时执行规则——规则自带的 `Accept-Language` 会覆盖默认值，没声明时才用这里的。
///
/// **地区是用户属性，不是站点属性**：服务端的引擎量得出「哪个语言版本拿得到内容」，
/// 量不出「用户想要哪个」。此前这一格在 `SafariRequestHeaderProvider` 里写死成
/// `zh-CN,zh;q=0.9,zh-TW;q=0.8,en;q=0.7`，于是繁中用户也会被按简中对待——
/// WEBTOON 对简中返回的是 `Error Language` 页，对繁中才返回正文。
struct DeviceAcceptLanguage {
    /// 最多取几个**系统偏好**标签。展开降级链之后条目会翻两三倍，因此这里取得少。
    static let maximumPreferredTags: Int = 3

    /// 权重档位：首个不带 `q`，其后 0.9 … 0.1，因此最多 10 条。
    static let maximumEntries: Int = 10

    /// 服务端（`accept_language.py`）的长度上限。超出即 400，因此在客户端按整条截断。
    static let maximumLength: Int = 200

    /// 服务端（`accept_language.py`）接受的字符集。设备标签理论上都在里面，
    /// 但取值来自系统、不是我们造的，因此在出口再过一道——不合的标签整条丢掉，
    /// 而不是把它塞进请求让服务端 400。
    private static let allowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-"
    )

    private let preferredLanguages: [String]

    init(preferredLanguages: [String] = Locale.preferredLanguages) {
        self.preferredLanguages = preferredLanguages
    }

    /// 组装成 `Accept-Language`：首个标签不带权重，其后每个递减 0.1。
    ///
    /// 例：`["zh-Hant-JP"]` → `zh-Hant-JP,zh-Hant;q=0.9,zh;q=0.8`。
    ///
    /// 中文注释：**每个标签都要展开它的 BCP-47 前缀降级链**（RFC 4647 lookup）。
    /// iOS 的 `Locale.preferredLanguages` 返回的是「语言偏好 × 设备地区」的组合——
    /// 设备语言繁中、地区日本时给出的是 `zh-Hant-JP`。按 RFC 4647 lookup 协商的站点
    /// 匹配的是 `zh-Hant` / `zh` 这一级，`zh-Hant-JP` 在严格匹配下一个都命不中。
    /// 2026-09-19 真机日志逮到：发出去的是 `zh-Hant-JP,zh-Hans-JP;q=0.9,en-JP;q=0.8,ja-JP;q=0.7`，
    /// 整串没有一条无地区标签。这是**串本身的形状缺陷**，与站点怎么反应无关。
    ///
    /// **收益面实测为零，不要据此推断站点行为**（引擎侧设计书 24.6，装置
    /// `scripts/measure_locale_prefix_chain_impact.py`）：线上 23 个入口用降级前后两种串
    /// 各取一次，主机 / HTTP 码 / 字节数 / 站内出边数全部相同，复取判噪后语言分流 0 个。
    /// 此处早先写的「站点会当成没有可用语言回落到默认语言，甚至回错误页」在该站集上不成立——
    /// 站点要么不按语言分流，要么像 WEBTOON 那样只认**首项的完整 `语言-地区` 标签**
    /// （`zh-Hant` / `zh` 单发都回英文站，`zh-Hant-TW` 在第二位也回英文站），
    /// 而那一级正是降级链按设计不生产的。保留本修法是因为形状缺陷确实存在、
    /// 且回滚同样零收益，不是因为它在现有站集上救回了什么。
    ///
    /// 降级链只取**真前缀**（`zh-Hant-JP` → `zh-Hant` → `zh`），不做地区映射——
    /// 把「繁中」映射成 `zh-TW` 那种是词表判据，本项目不采纳。
    ///
    /// 一个可用标签都没有时返回 `nil`——**宁可不发，也不发一个编出来的地区**：
    /// 服务端字段可选，不发时引擎退回它自己的默认值。
    func value() -> String? {
        let entries: [String] = self.preferredLanguages
            .compactMap(Self.sanitized)
            .reduced(to: Self.maximumPreferredTags)
            .flatMap(Self.prefixChain)
            .reduced(to: Self.maximumEntries)
        guard entries.isEmpty == false else {
            return nil
        }
        var assembled: String = ""
        for (index, tag): (Int, String) in entries.enumerated() {
            let piece: String
            if index == 0 {
                piece = tag
            } else {
                // 0.9, 0.8, 0.7 …… 与浏览器发出的形状一致。
                let weight: Double = 1.0 - (Double(index) * 0.1)
                piece = ",\(tag);q=\(String(format: "%.1f", weight))"
            }
            // 服务端超长即 400，因此按**整条**截断，不留半截标签。
            guard assembled.count + piece.count <= Self.maximumLength else {
                break
            }
            assembled += piece
        }
        return assembled.isEmpty ? nil : assembled
    }

    /// `zh-Hant-JP` → `["zh-Hant-JP", "zh-Hant", "zh"]`。只取真前缀，不猜地区。
    static func prefixChain(_ tag: String) -> [String] {
        let parts: [Substring] = tag.split(separator: "-")
        guard parts.count > 1 else {
            return [tag]
        }
        return (0..<parts.count).reversed().map { index in
            parts[0...index].joined(separator: "-")
        }
    }

    private static func sanitized(_ tag: String) -> String? {
        let trimmed: String = tag.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false, trimmed.count <= 35 else {
            return nil
        }
        guard trimmed.unicodeScalars.allSatisfy(Self.allowed.contains) else {
            return nil
        }
        return trimmed
    }
}

private extension Array where Element == String {
    /// 去重后截到上限。系统偶尔会给出重复标签（同一语言的不同区域写法）。
    func reduced(to limit: Int) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for tag: String in self {
            guard seen.insert(tag.lowercased()).inserted else {
                continue
            }
            result.append(tag)
            if result.count == limit {
                break
            }
        }
        return result
    }
}
