import Foundation

struct LoadRSSHubDiscoveryCandidatesUseCase {
    private let pageDataLoader: PageDataLoader
    private let rssHubBaseURLString: String
    private let jsonDecoder: JSONDecoder

    init(
        pageDataLoader: PageDataLoader,
        rssHubBaseURLString: String = "https://rsshub.app",
        jsonDecoder: JSONDecoder = JSONDecoder()
    ) {
        self.pageDataLoader = pageDataLoader
        self.rssHubBaseURLString = rssHubBaseURLString
        self.jsonDecoder = jsonDecoder
    }

    func execute(siteURL: URL) async throws -> [RSSHubDiscoveryCandidate] {
        guard let host: String = siteURL.host?.lowercased() else {
            throw DiscoverRSSFeedsError.invalidURL
        }

        let lookups: [RSSHubRadarDomainLookup] = self.domainLookups(host: host)
        self.logDiscoveryStarted(siteURL: siteURL, host: host, lookups: lookups)

        var lastError: Error?
        for lookup: RSSHubRadarDomainLookup in lookups {
            do {
                self.logLookupStarted(lookup)
                let rules: RSSHubRadarDomainRules = try await self.loadRules(domain: lookup.domain)
                let candidates: [RSSHubDiscoveryCandidate] = self.candidates(
                    rules: rules,
                    lookup: lookup,
                    siteURL: siteURL
                )

                if candidates.isEmpty == false {
                    self.logDiscoveryFinished(
                        siteURL: siteURL,
                        result: "matched",
                        candidateCount: candidates.count
                    )
                    return candidates
                }
            } catch {
                lastError = error
                self.logRuleLoadFailed(domain: lookup.domain, error: error)
            }
        }

        if let lastError: Error {
            self.logAllRuleLoadsFailed(host: host, error: lastError)
        }

        self.logDiscoveryFinished(siteURL: siteURL, result: "empty", candidateCount: 0)
        return []
    }

    private var requestConfig: RequestConfig {
        return RequestConfig(
            mergePolicy: .override,
            headers: APIRequestHeaders.rssHubHeaders()
        )
    }

    private func loadRules(domain: String) async throws -> RSSHubRadarDomainRules {
        let requestURL: URL = try self.requestURL(domain: domain)

        #if DEBUG
        print("[BrowseCraftRSSHub] request rules url=\(requestURL.absoluteString)")
        #endif

        let data: Data = try await self.pageDataLoader.getData(
            from: requestURL,
            request: self.requestConfig
        )
        let payload: RSSHubRadarDomainPayload = try self.jsonDecoder.decode(
            RSSHubRadarDomainPayload.self,
            from: data
        )
        self.logRulesLoaded(
            domain: domain,
            byteCount: data.count,
            rules: payload.domainRules
        )
        return payload.domainRules
    }

    private func requestURL(domain: String) throws -> URL {
        guard var components: URLComponents = URLComponents(string: self.rssHubBaseURLString) else {
            throw DiscoverRSSFeedsError.invalidURL
        }

        components.path = "/api/radar/rules/\(domain)"
        components.query = nil
        components.fragment = nil

        guard let url: URL = components.url else {
            throw DiscoverRSSFeedsError.invalidURL
        }

        return url
    }

    private func domainLookups(host: String) -> [RSSHubRadarDomainLookup] {
        let labels: [Substring] = host.split(separator: ".")
        guard labels.count >= 2 else {
            return [RSSHubRadarDomainLookup(domain: host, subdomain: nil)]
        }

        var lookups: [RSSHubRadarDomainLookup] = []
        for startIndex in 0...(labels.count - 2) {
            let domain: String = labels[startIndex...].joined(separator: ".")
            let subdomainLabels: ArraySlice<Substring> = labels[..<startIndex]
            let subdomain: String? = subdomainLabels.isEmpty ? nil : subdomainLabels.joined(separator: ".")
            lookups.append(RSSHubRadarDomainLookup(domain: domain, subdomain: subdomain))
        }

        return lookups
    }

    private func candidates(
        rules: RSSHubRadarDomainRules,
        lookup: RSSHubRadarDomainLookup,
        siteURL: URL
    ) -> [RSSHubDiscoveryCandidate] {
        guard let radarRules: [RSSHubRadarRule] = self.rulesToMatch(
            in: rules,
            subdomain: lookup.subdomain
        ) else {
            self.logNoSubdomainRules(domain: lookup.domain, subdomain: lookup.subdomain)
            return []
        }

        var candidates: [RSSHubDiscoveryCandidate] = []
        for rule in radarRules {
            guard let candidate: RSSHubDiscoveryCandidate = self.candidate(
                from: rule,
                domainName: rules.name,
                siteURL: siteURL
            ) else {
                continue
            }

            if candidates.contains(candidate) == false {
                candidates.append(candidate)
                self.logCandidateGenerated(rule: rule, candidate: candidate)
            } else {
                self.logDuplicateCandidate(rule: rule, candidate: candidate)
            }
        }

        #if DEBUG
        print(
            "[BrowseCraftRSSHub] matched rules " +
            "domain=\(lookup.domain) " +
            "subdomain=\(lookup.subdomain ?? "nil") " +
            "candidateCount=\(candidates.count)"
        )
        #endif

        return candidates
    }

    private func rulesToMatch(
        in rules: RSSHubRadarDomainRules,
        subdomain: String?
    ) -> [RSSHubRadarRule]? {
        if let subdomain: String,
           let rules: [RSSHubRadarRule] = rules.rulesBySubdomain[subdomain] {
            return rules
        }

        if subdomain == "www",
           let rules: [RSSHubRadarRule] = rules.rulesBySubdomain["."] {
            return rules
        }

        if subdomain == nil,
           let rules: [RSSHubRadarRule] = rules.rulesBySubdomain["www"] {
            return rules
        }

        return rules.rulesBySubdomain["."]
    }

    private func candidate(
        from rule: RSSHubRadarRule,
        domainName: String?,
        siteURL: URL
    ) -> RSSHubDiscoveryCandidate? {
        let path: String = self.matchPath(from: siteURL)
        for source in rule.source {
            for sourceTemplate in self.sourceTemplates(for: source) {
                guard let params: [String: String] = self.params(
                    matching: path,
                    sourceTemplate: sourceTemplate
                ) else {
                    self.logSourceTemplateMismatch(
                        title: rule.title,
                        source: source,
                        sourceTemplate: sourceTemplate,
                        path: path
                    )
                    continue
                }

                guard let targetPath: String = self.targetPath(rule.target, params: params) else {
                    self.logUnusableRule(
                        title: rule.title,
                        source: source,
                        target: rule.target,
                        reason: "missing-params",
                        params: params
                    )
                    continue
                }

                guard let feedURL: URL = self.rssHubFeedURL(path: targetPath) else {
                    self.logUnusableRule(
                        title: rule.title,
                        source: source,
                        target: rule.target,
                        reason: "invalid-feed-url",
                        params: params
                    )
                    continue
                }

                self.logRuleMatched(
                    title: rule.title,
                    source: source,
                    sourceTemplate: sourceTemplate,
                    target: rule.target,
                    targetPath: targetPath,
                    params: params
                )
                return RSSHubDiscoveryCandidate(
                    feedURL: feedURL,
                    title: self.title(domainName: domainName, ruleTitle: rule.title)
                )
            }
        }

        self.logUnusableRule(
            title: rule.title,
            source: rule.source.joined(separator: ","),
            target: rule.target,
            reason: "source-not-matched",
            params: [:]
        )
        return nil
    }

    private func matchPath(from url: URL) -> String {
        var path: String = url.path
        if path.hasSuffix("/"), path.count > 1 {
            path.removeLast()
        }
        return path.isEmpty ? "/" : path
    }

    private func sourceTemplates(for source: String) -> [String] {
        var templates: [String] = []
        var current: String = source
            .replacingOccurrences(
                of: #"(\/:\w+)\?(?=\/|$)"#,
                with: "$1",
                options: .regularExpression
            )

        templates.append(current)
        while let range: Range<String.Index> = current.range(
            of: #"\/:\w+$"#,
            options: .regularExpression
        ) {
            current.removeSubrange(range)
            templates.append(current.isEmpty ? "/" : current)
        }

        return templates
    }

    private func params(
        matching path: String,
        sourceTemplate: String
    ) -> [String: String]? {
        let pathSegments: [String] = self.pathSegments(path)
        let sourceSegments: [String] = self.pathSegments(sourceTemplate)
        guard pathSegments.count == sourceSegments.count else {
            return nil
        }

        var params: [String: String] = [:]
        for index in sourceSegments.indices {
            let sourceSegment: String = sourceSegments[index]
            let pathSegment: String = pathSegments[index]

            if sourceSegment.hasPrefix(":") {
                let name: String = self.parameterName(from: sourceSegment)
                guard name.isEmpty == false else {
                    return nil
                }
                params[name] = pathSegment
            } else if sourceSegment != pathSegment {
                return nil
            }
        }

        return params
    }

    private func parameterName(from segment: String) -> String {
        var name: String = String(segment.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "?"))
        if let range: Range<String.Index> = name.range(of: "{") {
            name = String(name[..<range.lowerBound])
        }
        return name
    }

    private func pathSegments(_ path: String) -> [String] {
        return path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .map(String.init)
    }

    private func targetPath(_ target: String, params: [String: String]) -> String? {
        var targetPath: String = self.targetPathByRemovingRegexRequirements(target)

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: #"/:(\w+)(\?)?(?=/|$)"#)
        } catch {
            return nil
        }

        while let match: NSTextCheckingResult = regex.firstMatch(
            in: targetPath,
            range: NSRange(targetPath.startIndex..<targetPath.endIndex, in: targetPath)
        ) {
            guard let fullRange: Range<String.Index> = Range(match.range(at: 0), in: targetPath),
                  let nameRange: Range<String.Index> = Range(match.range(at: 1), in: targetPath) else {
                return nil
            }

            let name: String = String(targetPath[nameRange])
            let optional: Bool = match.range(at: 2).location != NSNotFound
            if let value: String = params[name] {
                targetPath.replaceSubrange(fullRange, with: "/" + value)
            } else if optional {
                targetPath.removeSubrange(fullRange.lowerBound..<targetPath.endIndex)
                break
            } else {
                return nil
            }
        }

        return targetPath.hasPrefix("/") ? targetPath : "/" + targetPath
    }

    private func targetPathByRemovingRegexRequirements(_ target: String) -> String {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: #"/:\w+\{[^}]*\}(?=/|$)"#)
        } catch {
            return target
        }

        var result: String = target
        while let match: NSTextCheckingResult = regex.firstMatch(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        ) {
            guard let matchRange: Range<String.Index> = Range(match.range, in: result) else {
                return result
            }

            let matchText: String = String(result[matchRange])
            let cleaned: String = matchText.replacingOccurrences(
                of: #"\{[^}]*\}"#,
                with: "",
                options: .regularExpression
            )
            result.replaceSubrange(matchRange, with: cleaned)
        }

        return result
    }

    private func rssHubFeedURL(path: String) -> URL? {
        guard var components: URLComponents = URLComponents(string: self.rssHubBaseURLString) else {
            return nil
        }

        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func title(domainName: String?, ruleTitle: String) -> String {
        let trimmedDomainName: String? = domainName?.trimmedNonEmpty
        if let trimmedDomainName: String {
            return trimmedDomainName + " " + ruleTitle
        }

        return ruleTitle
    }

    private func logDiscoveryStarted(
        siteURL: URL,
        host: String,
        lookups: [RSSHubRadarDomainLookup]
    ) {
        #if DEBUG
        let lookupText: String = lookups
            .map { "\($0.domain)(subdomain=\($0.subdomain ?? "nil"))" }
            .joined(separator: " -> ")
        print(
            "[BrowseCraftRSSHub] discovery start " +
            "site=\(siteURL.absoluteString) host=\(host) lookups=[\(lookupText)]"
        )
        #endif
    }

    private func logLookupStarted(_ lookup: RSSHubRadarDomainLookup) {
        #if DEBUG
        print(
            "[BrowseCraftRSSHub] lookup start " +
            "domain=\(lookup.domain) subdomain=\(lookup.subdomain ?? "nil")"
        )
        #endif
    }

    private func logRulesLoaded(
        domain: String,
        byteCount: Int,
        rules: RSSHubRadarDomainRules
    ) {
        #if DEBUG
        let subdomains: [String] = rules.rulesBySubdomain.keys.sorted()
        let ruleCount: Int = rules.rulesBySubdomain.values.reduce(0) { count, rules in
            return count + rules.count
        }
        print(
            "[BrowseCraftRSSHub] rules loaded " +
            "domain=\(domain) bytes=\(byteCount) " +
            "name=\(rules.name ?? "nil") subdomains=\(subdomains) ruleCount=\(ruleCount)"
        )
        #endif
    }

    private func logDiscoveryFinished(
        siteURL: URL,
        result: String,
        candidateCount: Int
    ) {
        #if DEBUG
        print(
            "[BrowseCraftRSSHub] discovery finish " +
            "site=\(siteURL.absoluteString) result=\(result) candidateCount=\(candidateCount)"
        )
        #endif
    }

    private func logSourceTemplateMismatch(
        title: String,
        source: String,
        sourceTemplate: String,
        path: String
    ) {
        #if DEBUG
        print(
            "[BrowseCraftRSSHub] source mismatch " +
            "title=\(title) source=\(source) template=\(sourceTemplate) path=\(path)"
        )
        #endif
    }

    private func logRuleMatched(
        title: String,
        source: String,
        sourceTemplate: String,
        target: String,
        targetPath: String,
        params: [String: String]
    ) {
        #if DEBUG
        print(
            "[BrowseCraftRSSHub] rule matched " +
            "title=\(title) source=\(source) template=\(sourceTemplate) " +
            "target=\(target) targetPath=\(targetPath) params=\(self.logParams(params))"
        )
        #endif
    }

    private func logCandidateGenerated(
        rule: RSSHubRadarRule,
        candidate: RSSHubDiscoveryCandidate
    ) {
        #if DEBUG
        print(
            "[BrowseCraftRSSHub] candidate generated " +
            "title=\(rule.title) feed=\(candidate.feedURL.absoluteString)"
        )
        #endif
    }

    private func logDuplicateCandidate(
        rule: RSSHubRadarRule,
        candidate: RSSHubDiscoveryCandidate
    ) {
        #if DEBUG
        print(
            "[BrowseCraftRSSHub] candidate duplicate " +
            "title=\(rule.title) feed=\(candidate.feedURL.absoluteString)"
        )
        #endif
    }

    private func logRuleLoadFailed(domain: String, error: Error) {
        #if DEBUG
        print("[BrowseCraftRSSHub] rules load failed domain=\(domain) error=\(error)")
        #endif
    }

    private func logAllRuleLoadsFailed(host: String, error: Error) {
        #if DEBUG
        print("[BrowseCraftRSSHub] all rules load failed host=\(host) lastError=\(error)")
        #endif
    }

    private func logNoSubdomainRules(domain: String, subdomain: String?) {
        #if DEBUG
        print(
            "[BrowseCraftRSSHub] no subdomain rules " +
            "domain=\(domain) subdomain=\(subdomain ?? "nil")"
        )
        #endif
    }

    private func logUnusableRule(
        title: String,
        source: String,
        target: String,
        reason: String,
        params: [String: String]
    ) {
        #if DEBUG
        print(
            "[BrowseCraftRSSHub] skip rule " +
            "title=\(title) source=\(source) target=\(target) " +
            "reason=\(reason) params=\(self.logParams(params))"
        )
        #endif
    }

    private func logParams(_ params: [String: String]) -> String {
        guard params.isEmpty == false else {
            return "{}"
        }

        let pairs: [String] = params.keys.sorted().map { key in
            return "\(key)=\(params[key] ?? "")"
        }
        return "{" + pairs.joined(separator: ",") + "}"
    }
}

struct RSSHubDiscoveryCandidate: Hashable {
    var feedURL: URL
    var title: String
}

private struct RSSHubRadarDomainLookup {
    var domain: String
    var subdomain: String?
}

private struct RSSHubRadarDomainPayload: Decodable {
    let domainRules: RSSHubRadarDomainRules

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<RSSHubRadarDynamicCodingKey> = try decoder.container(
            keyedBy: RSSHubRadarDynamicCodingKey.self
        )
        var name: String?
        var rulesBySubdomain: [String: [RSSHubRadarRule]] = [:]

        for key in container.allKeys {
            if key.stringValue == "_name" {
                name = try container.decodeIfPresent(String.self, forKey: key)
            } else if key.stringValue.hasPrefix("_") == false {
                rulesBySubdomain[key.stringValue] = try container.decodeIfPresent(
                    [RSSHubRadarRule].self,
                    forKey: key
                )
            }
        }

        self.domainRules = RSSHubRadarDomainRules(
            name: name,
            rulesBySubdomain: rulesBySubdomain
        )
    }
}

private struct RSSHubRadarDomainRules {
    var name: String?
    var rulesBySubdomain: [String: [RSSHubRadarRule]]
}

private struct RSSHubRadarRule: Decodable {
    var title: String
    var docs: String?
    var source: [String]
    var target: String

    private enum CodingKeys: String, CodingKey {
        case title
        case docs
        case source
        case target
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "RSSHub"
        self.docs = try container.decodeIfPresent(String.self, forKey: .docs)
        self.target = try container.decode(String.self, forKey: .target)

        if let sources: [String] = try? container.decode([String].self, forKey: .source) {
            self.source = sources
        } else if let source: String = try? container.decode(String.self, forKey: .source) {
            self.source = [source]
        } else {
            self.source = []
        }
    }
}

private struct RSSHubRadarDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
