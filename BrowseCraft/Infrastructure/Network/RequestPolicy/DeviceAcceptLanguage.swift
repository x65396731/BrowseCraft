import Foundation

/// 设备/用户实际地区推出的 `Accept-Language`（`BC-ACQ-062`）。
///
/// 中文注释：这是**地区取值的单一定义点**。三处读同一个值，三端因此到达同一个页面：
///
/// 1. 预检取页（`PreflightHTTPPageLoader` / `PreflightRenderedPageLoader` 经
///    `ChromeRequestHeaderProvider`）；
/// 2. 提交生成任务时随请求发给服务端（`PortalRuleGenerationRequest.acceptLanguage`），
///    引擎拿它作语言头候选表的第一项并写进规则；
/// 3. 运行时执行规则——规则自带的 `Accept-Language` 会覆盖默认值，没声明时才用这里的。
///
/// **地区是用户属性，不是站点属性**：服务端的引擎量得出「哪个语言版本拿得到内容」，
/// 量不出「用户想要哪个」。此前这一格在 `ChromeRequestHeaderProvider` 里写死成
/// `zh-CN,zh;q=0.9,zh-TW;q=0.8,en;q=0.7`，于是繁中用户也会被按简中对待——
/// WEBTOON 对简中返回的是 `Error Language` 页，对繁中才返回正文。
struct DeviceAcceptLanguage {
    /// 最多带几个语言标签。浏览器通常 2–4 个；服务端上限 200 字符，取 4 个留足余量。
    static let maximumTags: Int = 4

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

    /// 组装成 `Accept-Language`：首选标签不带权重，其后每个递减 0.1。
    ///
    /// 例：`["zh-Hant-TW", "en-US"]` → `zh-Hant-TW,en-US;q=0.9`。
    /// 一个可用标签都没有时返回 `nil`——**宁可不发，也不发一个编出来的地区**：
    /// 服务端字段可选，不发时引擎退回它自己的默认值。
    func value() -> String? {
        let tags: [String] = self.preferredLanguages
            .compactMap(Self.sanitized)
            .reduced(to: Self.maximumTags)
        guard tags.isEmpty == false else {
            return nil
        }
        return tags.enumerated().map { index, tag in
            guard index > 0 else {
                return tag
            }
            // 0.9, 0.8, 0.7 —— 与浏览器发出的形状一致。
            let weight: Double = 1.0 - (Double(index) * 0.1)
            return "\(tag);q=\(String(format: "%.1f", weight))"
        }.joined(separator: ",")
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
