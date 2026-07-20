import Foundation
import SwiftUI
import WebKit

@MainActor
final class VideoWebPlayerCoordinator: NSObject, ObservableObject {
    enum Dialog {
        case alert(String, CheckedContinuation<Void, Never>)
        case confirm(String, CheckedContinuation<Bool, Never>)
        case prompt(String, String, CheckedContinuation<String?, Never>)

        var needsCancel: Bool {
            switch self {
            case .alert:
                return false
            case .confirm, .prompt:
                return true
            }
        }

        var message: String {
            switch self {
            case .alert(let message, _):
                return message
            case .confirm(let message, _):
                return message
            case .prompt(let prompt, _, _):
                return prompt
            }
        }
    }

    @Published var dialog: Dialog?
    @Published var isShowingDialog: Bool = false
    @Published var promptInput: String = ""

    let configuration: WKWebViewConfiguration
    let initialHost: String?

    init(request: VideoWebPlayerRequest) {
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.configuration = configuration
        self.initialHost = request.url.host?.lowercased()
        super.init()
    }

    /// 中文注释：把本次播放即时解析出的 Cookie 注入 WebKit store，后续 iframe/媒体子请求无需持久化 Cookie 到历史记录。
    func prepareCookies(
        for request: VideoWebPlayerRequest,
        completion: @escaping @MainActor () -> Void
    ) {
        guard let cookieHeader: String = request.headers.first(where: { key, _ in
            return key.caseInsensitiveCompare("Cookie") == .orderedSame
        })?.value else {
            completion()
            return
        }
        let cookies: [HTTPCookie] = self.cookies(from: cookieHeader, url: request.url)
        guard cookies.isEmpty == false else {
            completion()
            return
        }
        let cookieStore: WKHTTPCookieStore = self.configuration.websiteDataStore.httpCookieStore
        let group: DispatchGroup = DispatchGroup()
        for cookie: HTTPCookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in
                completion()
            }
        }
    }

    private func cookies(from header: String, url: URL) -> [HTTPCookie] {
        guard let host: String = url.host else {
            return []
        }
        return header.split(separator: ";").compactMap { component in
            let pair: [Substring] = component.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else {
                return nil
            }
            let name: String = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value: String = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else {
                return nil
            }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host,
                .path: "/",
                .name: name,
                .value: value
            ]
            if url.scheme?.lowercased() == "https" {
                properties[.secure] = "TRUE"
            }
            return HTTPCookie(properties: properties)
        }
    }

    func confirmDialog() {
        guard let dialog: Dialog = self.dialog else {
            return
        }

        self.isShowingDialog = false
        self.dialog = nil

        switch dialog {
        case .alert(_, let continuation):
            continuation.resume()
        case .confirm(_, let continuation):
            continuation.resume(returning: true)
        case .prompt(_, _, let continuation):
            continuation.resume(returning: self.promptInput)
        }
    }

    func cancelDialog() {
        guard let dialog: Dialog = self.dialog else {
            return
        }

        self.isShowingDialog = false
        self.dialog = nil

        switch dialog {
        case .alert(_, let continuation):
            continuation.resume()
        case .confirm(_, let continuation):
            continuation.resume(returning: false)
        case .prompt(_, _, let continuation):
            continuation.resume(returning: nil)
        }
    }

    func showDialog(_ dialog: Dialog) {
        self.dialog = dialog
        self.isShowingDialog = true
    }
}
