import Foundation
import ReadiumShared

// 中文注释：站点有声作品的音频请求客户端。AVFoundation 只看到 Readium 的自定义 scheme（readiumhttp://…），
// 真正发网络请求的是这里的 DefaultHTTPClient——App 没有全局 ATS 例外，http 地址在这里升级成 https 再发
//（2026-09-14 loyalbooks 模拟器复验：规则产出的 mp3 是 http://www.archive.org/…，URLSession 报 -1022 被 ATS 拦下）。
// DefaultHTTPClient 对代理是弱引用，本对象由出版物容器持有。

final class SiteBookAudioHTTPClient: DefaultHTTPClientDelegate, @unchecked Sendable {
    let client: DefaultHTTPClient

    init(configuration: URLSessionConfiguration = .default) {
        self.client = DefaultHTTPClient(configuration: configuration)
        self.client.delegate = self
    }

    func httpClient(_ httpClient: DefaultHTTPClient, willStartRequest request: HTTPRequest) async -> HTTPResult<HTTPRequestConvertible> {
        return .success(Self.upgradedToHTTPS(request))
    }

    /// 中文注释：http → https，其余原样；升级后不再回退 http（回退也会被 ATS 拦，没有意义）。
    static func upgradedToHTTPS(_ request: HTTPRequest) -> HTTPRequest {
        let url: URL = request.url.url
        guard url.scheme?.lowercased() == "http",
              var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return request
        }
        components.scheme = "https"
        guard let upgradedURL: URL = components.url, let httpURL: HTTPURL = HTTPURL(url: upgradedURL) else {
            return request
        }
        var upgraded: HTTPRequest = request
        upgraded.url = httpURL
        return upgraded
    }
}
