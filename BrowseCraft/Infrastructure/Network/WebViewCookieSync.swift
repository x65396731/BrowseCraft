import Foundation

// 中文注释：WebViewCookieSync.swift 负责把 WebView 渲染路径拿到的站点 Cookie 同步回系统 Cookie 存储。
//
// 2026-10-07 半夏小說（xbanxia）真机：列表页直接请求收到 Cloudflare 挑战，`BCA-RUNTIME-005` 改走 WebView 过了挑战、
// 列表正常；但放行 Cookie（`cf_clearance`，域 `.xbanxia.cc`）只在 `WKHTTPCookieStore`，封面请求读 `HTTPCookieStorage.shared`，
// 日志 `stage=image urlHost=image.xbanxia.cc hasCookie=false` → 图床同样回挑战页、封面全部 `dataLoadingFailed`。
// 此前只有「系统 → WebView」一个方向的拷贝（`WKWebViewHTMLLoadOperation.prepareCookieStore`）。

/// 中文注释：只挑「对这个主机生效」的 Cookie——域名等于主机，或主机是该域名的子域（`.xbanxia.cc` 覆盖 `www.` 与 `image.`）。
/// 放行 Cookie 绑定 UA；封面请求与 WebView 都用规则 `sharedRequest` 的同一个 UA（`BC-ACQ-070`），这里不改 UA。
enum WebViewCookieSync {
    static func cookiesApplying(to host: String, from cookies: [HTTPCookie]) -> [HTTPCookie] {
        let normalizedHost: String = host.lowercased()
        guard normalizedHost.isEmpty == false else {
            return []
        }
        return cookies.filter { cookie in
            var domain: String = cookie.domain.lowercased()
            if domain.hasPrefix(".") {
                domain.removeFirst()
            }
            guard domain.isEmpty == false else {
                return false
            }
            return normalizedHost == domain || normalizedHost.hasSuffix("." + domain)
        }
    }

    /// 中文注释：把 WebView 里对 `url` 主机生效的 Cookie 写进 `storage`（默认系统共享存储）。返回写入条数。
    @discardableResult
    static func copy(
        _ cookies: [HTTPCookie],
        applyingTo url: URL,
        into storage: HTTPCookieStorage = .shared
    ) -> Int {
        guard let host: String = url.host else {
            return 0
        }
        let matched: [HTTPCookie] = self.cookiesApplying(to: host, from: cookies)
        for cookie: HTTPCookie in matched {
            storage.setCookie(cookie)
        }
        return matched.count
    }
}
