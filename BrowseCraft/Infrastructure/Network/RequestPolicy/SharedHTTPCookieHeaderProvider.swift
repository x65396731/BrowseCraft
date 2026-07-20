import Foundation

struct SharedHTTPCookieHeaderProvider: SystemCookieHeaderProviding {
    func cookieHeader(for url: URL) -> String? {
        guard let cookies: [HTTPCookie] = HTTPCookieStorage.shared.cookies(for: url),
              cookies.isEmpty == false else {
            return nil
        }

        return cookies
            .map { cookie in "\(cookie.name)=\(cookie.value)" }
            .joined(separator: "; ")
    }
}
