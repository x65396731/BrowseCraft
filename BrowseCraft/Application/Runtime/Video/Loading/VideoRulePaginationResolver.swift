import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：VideoRulePaginationResolver 只解释 Video V2 P0 数字 placeholder 分页合同。
// 它不发起请求、不解析 DOM，也不猜测 next-link/API/cursor 分页。
struct VideoRulePaginationResolution {
    let currentPage: Int
    let configuredPageURL: URL
    let nextPage: SourcePagination?
    let stopWhenEmpty: Bool?
}

struct VideoRulePaginationResolver {
    func resolve(
        page: VideoPageRule,
        listRule: VideoListRule,
        requestedPage: Int,
        baseURL: String,
        sourceID: String
    ) throws -> VideoRulePaginationResolution {
        guard requestedPage > 0 else {
            throw SourceRuntimeError.invalidInput(
                "Video V2 list page must be greater than zero: \(requestedPage)."
            )
        }

        guard let pagination: PaginationRule = listRule.pagination else {
            guard requestedPage == 1 else {
                throw SourceRuntimeError.unsupported(
                    .custom(
                        "Video V2 list rule \(listRule.id) does not declare pagination; page \(requestedPage) cannot be requested."
                    )
                )
            }
            if page.url.contains("{page}") {
                throw self.ruleConfigurationError(
                    sourceID: sourceID,
                    reason: "Video page \(page.id) contains {page} without a pagination contract."
                )
            }

            return VideoRulePaginationResolution(
                currentPage: requestedPage,
                configuredPageURL: try self.pageURL(
                    page.url,
                    baseURL: baseURL,
                    sourceID: sourceID
                ),
                nextPage: nil,
                stopWhenEmpty: nil
            )
        }

        let contract: PaginationContract = try self.contract(
            pagination,
            page: page,
            listRule: listRule,
            sourceID: sourceID
        )
        switch contract {
        case .singlePage(let url):
            guard requestedPage == 1 else {
                throw SourceRuntimeError.unsupported(
                    .custom(
                        "Video page \(page.id) disables inherited pagination; page \(requestedPage) cannot be requested."
                    )
                )
            }

            return VideoRulePaginationResolution(
                currentPage: requestedPage,
                configuredPageURL: try self.pageURL(
                    url,
                    baseURL: baseURL,
                    sourceID: sourceID
                ),
                nextPage: nil,
                stopWhenEmpty: nil
            )
        case .paginated(let template, let placeholder, let maxPages, let stopWhenEmpty):
            if let maxPages,
               requestedPage > maxPages {
                throw SourceRuntimeError.invalidInput(
                    "Video V2 requested page \(requestedPage) exceeds maxPages=\(maxPages) for list rule \(listRule.id)."
                )
            }

            let configuredPageURL: URL = try self.pageURL(
                self.replacingPage(
                    in: template,
                    placeholder: placeholder,
                    page: requestedPage
                ),
                baseURL: baseURL,
                sourceID: sourceID
            )
            let nextPage: SourcePagination?
            if let maxPages,
               requestedPage >= maxPages {
                nextPage = nil
            } else {
                guard requestedPage < Int.max else {
                    throw SourceRuntimeError.invalidInput(
                        "Video V2 requested page cannot advance beyond Int.max for list rule \(listRule.id)."
                    )
                }
                let nextPageNumber: Int = requestedPage + 1
                let nextPageURL: URL = try self.pageURL(
                    self.replacingPage(
                        in: template,
                        placeholder: placeholder,
                        page: nextPageNumber
                    ),
                    baseURL: baseURL,
                    sourceID: sourceID
                )
                nextPage = SourcePagination.next(
                    nextPageURL: nextPageURL,
                    nextPage: nextPageNumber
                )
            }

            return VideoRulePaginationResolution(
                currentPage: requestedPage,
                configuredPageURL: configuredPageURL,
                nextPage: nextPage,
                stopWhenEmpty: stopWhenEmpty
            )
        }
    }

    private func contract(
        _ pagination: PaginationRule,
        page: VideoPageRule,
        listRule: VideoListRule,
        sourceID: String
    ) throws -> PaginationContract {
        guard pagination.nextPage == nil else {
            throw self.ruleConfigurationError(
                sourceID: sourceID,
                reason: "Video V2 P0 list rule \(listRule.id) does not support nextPage pagination."
            )
        }
        guard let placeholder: String = pagination.pagePlaceholder?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              placeholder.isEmpty == false else {
            throw self.ruleConfigurationError(
                sourceID: sourceID,
                reason: "Video V2 list rule \(listRule.id) requires a non-empty pagePlaceholder."
            )
        }
        guard let stopWhenEmpty: Bool = pagination.stopWhenEmpty else {
            throw self.ruleConfigurationError(
                sourceID: sourceID,
                reason: "Video V2 list rule \(listRule.id) must explicitly declare stopWhenEmpty."
            )
        }
        if let maxPages: Int = pagination.maxPages,
           maxPages <= 0 {
            throw self.ruleConfigurationError(
                sourceID: sourceID,
                reason: "Video V2 list rule \(listRule.id) maxPages must be greater than zero."
            )
        }

        let rawPageURLTemplate: String? = page.pageURLTemplate?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if page.pageURLTemplate != nil,
           rawPageURLTemplate?.isEmpty != false {
            return .singlePage(url: page.url)
        }
        let pageURLTemplate: String? = rawPageURLTemplate?.isEmpty == false
            ? rawPageURLTemplate
            : nil
        let rawListURLTemplate: String? = pagination.urlTemplate?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let listURLTemplate: String? = rawListURLTemplate?.isEmpty == false
            ? rawListURLTemplate
            : nil
        let template: String = pageURLTemplate ?? listURLTemplate ?? page.url

        let occurrenceCount: Int = template.components(separatedBy: placeholder).count - 1
        guard occurrenceCount == 1 else {
            throw self.ruleConfigurationError(
                sourceID: sourceID,
                reason: pageURLTemplate == nil && listURLTemplate == nil
                    ? "Video page \(page.id) must contain pagination placeholder \(placeholder) exactly once."
                    : pageURLTemplate != nil
                        ? "Video page \(page.id) pageURLTemplate must contain pagination placeholder \(placeholder) exactly once."
                        : "Video list rule \(listRule.id) urlTemplate must contain pagination placeholder \(placeholder) exactly once."
            )
        }

        return .paginated(
            template: template,
            placeholder: placeholder,
            maxPages: pagination.maxPages,
            stopWhenEmpty: stopWhenEmpty
        )
    }

    private func replacingPage(
        in template: String,
        placeholder: String,
        page: Int
    ) -> String {
        return template.replacingOccurrences(
            of: placeholder,
            with: String(page)
        )
    }

    private func pageURL(
        _ rawURL: String,
        baseURL: String,
        sourceID: String
    ) throws -> URL {
        guard let baseURL: URL = URL(string: baseURL),
              let url: URL = URL(string: rawURL, relativeTo: baseURL)?.absoluteURL,
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw self.ruleConfigurationError(
                sourceID: sourceID,
                reason: "Video V2 page URL is invalid: \(rawURL)."
            )
        }
        return url
    }

    private func ruleConfigurationError(
        sourceID: String,
        reason: String
    ) -> RuleExecutionError {
        return RuleExecutionError.ruleConfiguration(
            stage: .list,
            sourceID: sourceID,
            reason: reason
        )
    }
}

private enum PaginationContract {
    case singlePage(url: String)
    case paginated(
        template: String,
        placeholder: String,
        maxPages: Int?,
        stopWhenEmpty: Bool
    )
}
