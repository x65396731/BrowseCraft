import SwiftUI

private struct BrowserRequestHeaderProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any BrowserRequestHeaderProviding = EmptyBrowserRequestHeaderProvider()
}

private struct SystemCookieHeaderProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any SystemCookieHeaderProviding = EmptySystemCookieHeaderProvider()
}

extension EnvironmentValues {
    var browserRequestHeaderProvider: any BrowserRequestHeaderProviding {
        get { self[BrowserRequestHeaderProviderEnvironmentKey.self] }
        set { self[BrowserRequestHeaderProviderEnvironmentKey.self] = newValue }
    }

    var systemCookieHeaderProvider: any SystemCookieHeaderProviding {
        get { self[SystemCookieHeaderProviderEnvironmentKey.self] }
        set { self[SystemCookieHeaderProviderEnvironmentKey.self] = newValue }
    }
}
