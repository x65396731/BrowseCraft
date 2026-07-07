import Foundation
import BrowseCraftCore

// 中文注释：VideoRequestConfigResolver 集中处理视频 runtime 的请求配置合并，避免 list/detail/play 三条链路各写一套。
enum VideoRequestStage {
    case list
    case detail
    case play
}

struct VideoRequestConfigResolver {
    func request(
        for stage: VideoRequestStage,
        definition: VideoSourceDefinition,
        context: SourceRuntimeContext
    ) -> RequestConfig? {
        let stageRequest: RequestConfig?
        switch stage {
        case .list:
            stageRequest = definition.listRequest
        case .detail:
            stageRequest = definition.detailRequest
        case .play:
            stageRequest = definition.playRequest
        }

        let sharedAndStage: RequestConfig? = self.merged(
            base: definition.sharedRequest,
            override: stageRequest
        )
        return self.merged(
            base: sharedAndStage,
            override: self.requestConfig(from: context.requestOverride)
        )
    }

    func requestLog(
        url: URL,
        request: RequestConfig?,
        html: String? = nil
    ) -> SourceRequestLog {
        return SourceRequestLog(
            url: url,
            method: request?.method?.rawValue ?? "GET",
            headerCount: request?.headers?.count ?? 0,
            contentLength: html?.utf8.count
        )
    }

    func emptyListIssues(items: [SourceContentItem]) -> [SourceRuntimeIssue] {
        guard items.isEmpty else {
            return []
        }

        return [
            SourceRuntimeIssue(
                id: "video.selectorEmpty",
                severity: .warning,
                message: "Video list produced no preview items."
            )
        ]
    }

    func playbackIssues(reference: SourceVideoPlaybackReference) -> [SourceRuntimeIssue] {
        switch reference.status {
        case .failed(.mediaURLNotFound):
            return [
                SourceRuntimeIssue(
                    id: "video.mediaURLNotFound",
                    severity: .warning,
                    message: "Video playback page did not expose a playable media URL."
                )
            ]
        case .restricted(.captchaOrAntiBot):
            return [
                SourceRuntimeIssue(
                    id: "video.blockedByAntiBot",
                    severity: .error,
                    message: "Video playback page appears to be blocked by anti-bot or captcha protection."
                )
            ]
        case .playable, .pageOnly, .restricted(_), .failed(_):
            return []
        }
    }

    func mappedLoadingError(_ error: Error, url: URL) -> Error {
        if let ruleError: RuleExecutionError = error as? RuleExecutionError {
            switch ruleError {
            case .antiBot:
                return SourceRuntimeError.unsupported(
                    .custom("video.blockedByAntiBot: \(url.absoluteString)")
                )
            case .network, .selectorEmpty, .ruleConfiguration, .unknown:
                return error
            }
        }

        return error
    }

    private func merged(base: RequestConfig?, override: RequestConfig?) -> RequestConfig? {
        guard let override: RequestConfig else {
            return base
        }

        guard let base: RequestConfig else {
            return override
        }

        if override.mergePolicy == .override {
            return override
        }

        var headers: [String: String] = base.headers ?? [:]
        override.headers?.forEach { key, value in
            headers[key] = value
        }

        return RequestConfig(
            scope: override.scope ?? base.scope,
            mergePolicy: override.mergePolicy ?? base.mergePolicy,
            method: override.method ?? base.method,
            headers: headers.isEmpty ? nil : headers,
            body: override.body ?? base.body,
            cookiePolicy: override.cookiePolicy ?? base.cookiePolicy,
            cookiePriority: override.cookiePriority ?? base.cookiePriority,
            cookieScope: override.cookieScope ?? base.cookieScope,
            charset: override.charset ?? base.charset,
            needsWebView: override.needsWebView ?? base.needsWebView,
            autoScroll: override.autoScroll ?? base.autoScroll,
            imageHeaders: override.imageHeaders ?? base.imageHeaders,
            imageRequest: override.imageRequest ?? base.imageRequest
        )
    }

    private func requestConfig(from override: SourceRequestOverride?) -> RequestConfig? {
        guard let override: SourceRequestOverride else {
            return nil
        }

        return RequestConfig(
            method: self.httpMethod(from: override.method),
            headers: override.headers.isEmpty ? nil : override.headers,
            body: override.body.map { value in
                return RequestBody(value: value)
            },
            cookiePolicy: self.cookiePolicy(from: override.cookiePolicy),
            charset: self.charset(from: override.charset),
            needsWebView: override.requiresWebView,
            autoScroll: override.autoScroll
        )
    }

    private func httpMethod(from value: String?) -> HTTPMethod? {
        guard let normalized: String = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              normalized.isEmpty == false else {
            return nil
        }

        return HTTPMethod(rawValue: normalized)
    }

    private func charset(from value: String?) -> Charset? {
        guard let normalized: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              normalized.isEmpty == false else {
            return nil
        }

        return Charset(rawValue: normalized)
    }

    private func cookiePolicy(from value: SourceRequestCookiePolicy?) -> CookiePolicy? {
        switch value {
        case .some(.none):
            return CookiePolicy.none
        case .some(.read), .some(.write), .some(.readWrite):
            return .browser
        case nil:
            return nil
        }
    }
}
