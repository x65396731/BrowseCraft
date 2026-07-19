import Foundation
import BrowseCraftCore

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
        if let maxPages: Int = contract.maxPages,
           requestedPage > maxPages {
            throw SourceRuntimeError.invalidInput(
                "Video V2 requested page \(requestedPage) exceeds maxPages=\(maxPages) for list rule \(listRule.id)."
            )
        }

        let configuredPageURL: URL = try self.pageURL(
            self.replacingPage(
                in: page.url,
                placeholder: contract.placeholder,
                page: requestedPage
            ),
            baseURL: baseURL,
            sourceID: sourceID
        )
        let nextPage: SourcePagination?
        if let maxPages: Int = contract.maxPages,
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
                    in: page.url,
                    placeholder: contract.placeholder,
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
            stopWhenEmpty: contract.stopWhenEmpty
        )
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

        let occurrenceCount: Int = page.url.components(separatedBy: placeholder).count - 1
        guard occurrenceCount == 1 else {
            throw self.ruleConfigurationError(
                sourceID: sourceID,
                reason: "Video page \(page.id) must contain pagination placeholder \(placeholder) exactly once."
            )
        }

        return PaginationContract(
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

private struct PaginationContract {
    let placeholder: String
    let maxPages: Int?
    let stopWhenEmpty: Bool
}
