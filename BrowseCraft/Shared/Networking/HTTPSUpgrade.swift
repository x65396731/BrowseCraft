import Foundation

/// 中文注释：`http://` 地址升成 `https://` 的单一定义点。
///
/// ATS 拒绝明文 http（不开全局例外），而站点页面里仍常写 http 链接、服务端再 301 到 https
/// （2026-09-21 sfacg 作品地址 `http://manhua.sfacg.com/...`）。页面请求、跳转目标、图片请求都经这里升级；
/// 规则生成引擎的采集端同样先升级再取，两端到达同一页面。
enum HTTPSUpgrade {
    /// 本来就是 https 或不是 http(s) 即 nil（调用方原样使用）。
    static func upgraded(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http",
              var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        if components.port == 80 {
            components.port = nil
        }
        return components.url
    }
}
