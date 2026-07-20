import Foundation

struct ChromeRequestHeaderProvider: BrowserRequestHeaderProviding {
    let userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"

    private let chromeMajorVersion: String = "150"

    func defaultHeaders(
        for url: URL,
        referer: URL?,
        includeOrigin: Bool
    ) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": self.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
            "Accept-Language": "zh-CN,zh;q=0.9,zh-TW;q=0.8,en;q=0.7",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "Priority": "u=0, i",
            "Sec-CH-UA": "\"Not;A=Brand\";v=\"8\", \"Chromium\";v=\"\(self.chromeMajorVersion)\", \"Google Chrome\";v=\"\(self.chromeMajorVersion)\"",
            "Sec-CH-UA-Mobile": "?0",
            "Sec-CH-UA-Platform": "\"macOS\"",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-User": "?1",
            "Upgrade-Insecure-Requests": "1"
        ]
        if let referer: URL {
            headers["Referer"] = referer.absoluteString
        }
        if includeOrigin,
           let origin: String = RequestHeaderFields.originHeader(from: referer ?? url) {
            headers["Origin"] = origin
        }
        return headers
    }
}
