enum SourceAPIRequestHeaders {
    static func catalogHeaders(base: [String: String]) -> [String: String] {
        var headers: [String: String] = base
        headers["Accept"] = "application/json"
        return headers
    }

    static func rssHubHeaders(base: [String: String] = [:]) -> [String: String] {
        var headers: [String: String] = base
        headers["Accept"] = "application/json"
        return headers
    }

    static func rssFeedHeaders(base: [String: String] = [:]) -> [String: String] {
        var headers: [String: String] = base
        headers["Accept"] = "application/rss+xml,application/atom+xml,application/xml;q=0.9,text/xml;q=0.8,*/*;q=0.1"
        return headers
    }
}
