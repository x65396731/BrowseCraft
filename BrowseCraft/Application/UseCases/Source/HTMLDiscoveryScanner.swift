import Foundation

// 中文注释：HTMLDiscoveryScanner 只保留 URL、文本和候选过滤等纯 Application 逻辑。
struct HTMLDiscoveryScanner {
    private let urlResolver: URLResolvingService

    init(urlResolver: URLResolvingService = URLResolvingService()) {
        self.urlResolver = urlResolver
    }

    func siteURL(from rawValue: String) throws -> URL {
        let trimmed: String = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            normalized = trimmed
        } else {
            normalized = "https://\(trimmed)"
        }

        guard let url: URL = URL(string: normalized),
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw URLResolvingError.invalidURL(rawValue)
        }

        return url
    }

    func candidateSearchURLs(
        siteURL: URL,
        keyword: String,
        preferredPathBuilders: [(String) -> [String]],
        additionalRawCandidates: [String]
    ) -> [URL] {
        var urls: [URL] = []
        guard keyword.isEmpty == false,
              let encodedKeyword: String = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return [siteURL]
        }

        let baseURLString: String = siteURL.absoluteString
        let root: String = "\(siteURL.scheme ?? "https")://\(siteURL.host ?? "")"
        let sitePath: String = siteURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var preferredCandidates: [String] = preferredPathBuilders.flatMap { builder in
            builder(encodedKeyword)
        }
        if sitePath.isEmpty == false {
            let scopedPath: String = "/\(sitePath)"
            preferredCandidates.append("\(scopedPath)/search?keyword=\(encodedKeyword)")
            preferredCandidates.append("\(scopedPath)/search?q=\(encodedKeyword)")
        }

        let rawCandidates: [String] = preferredCandidates + [
            "/search?keyword=\(encodedKeyword)",
            "/search?q=\(encodedKeyword)",
            "/search?wd=\(encodedKeyword)",
            "/?s=\(encodedKeyword)",
            "/search/\(encodedKeyword)",
            "/so/\(encodedKeyword)"
        ] + additionalRawCandidates + [
            siteURL.path.isEmpty || siteURL.path == "/" ? "/" : siteURL.path
        ]

        for rawCandidate: String in rawCandidates {
            let absoluteString: String = self.urlResolver.absoluteString(rawCandidate, baseURLString: root)
            if let url: URL = URL(string: absoluteString),
               urls.contains(url) == false {
                urls.append(url)
            }
        }

        if let url: URL = URL(string: baseURLString), urls.contains(url) == false {
            urls.append(url)
        }

        return urls
    }

    func bestTitle(anchor: HTMLDiscoveryAnchorSnapshot, fallback: String) -> String {
        if fallback.isEmpty == false {
            return fallback
        }

        let title: String = self.normalizedText(anchor.title)
        if title.isEmpty == false {
            return title
        }

        return self.normalizedText(anchor.imageAlt)
    }

    func normalizedText(_ text: String) -> String {
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { part in part.isEmpty == false }
            .joined(separator: " ")
    }

    func isUsableCoverURLString(_ value: String) -> Bool {
        return value.isEmpty == false
            && value.hasPrefix("data:") == false
            && value.hasPrefix("blob:") == false
            && value != "#"
    }

    func isBlockedCoverURLString(_ value: String) -> Bool {
        let lowercasedValue: String = value.lowercased()
        return lowercasedValue.hasSuffix(".svg")
            || lowercasedValue.contains("/logo")
            || lowercasedValue.contains("logo-")
    }
}
