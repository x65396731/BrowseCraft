import Foundation
import BrowseCraftCore

// 中文注释：VideoRequestConfigResolver 只选择 legacy stage 请求，合并语义统一委托给 Core。
enum VideoRequestStage {
    case list
    case detail
    case play
}

struct VideoRequestConfigResolver {
    private let requestConfigResolver: RequestConfigResolver
    private let sourceRequestOverrideResolver: SourceRequestOverrideResolver

    init(
        requestConfigResolver: RequestConfigResolver = RequestConfigResolver(),
        sourceRequestOverrideResolver: SourceRequestOverrideResolver = SourceRequestOverrideResolver()
    ) {
        self.requestConfigResolver = requestConfigResolver
        self.sourceRequestOverrideResolver = sourceRequestOverrideResolver
    }

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

        let sharedAndStage: RequestConfig? = self.requestConfigResolver.resolve(
            definition.sharedRequest,
            stageRequest
        )
        return self.sourceRequestOverrideResolver.resolve(
            base: sharedAndStage,
            override: context.requestOverride
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
        case .failed(.iframePlayerDepthExceeded):
            return [
                SourceRuntimeIssue(
                    id: "video.iframePlayerDepthExceeded",
                    severity: .warning,
                    message: "Video playback iframe player exceeded the supported depth."
                )
            ]
        case .failed(.iframePlayerLoopDetected):
            return [
                SourceRuntimeIssue(
                    id: "video.iframePlayerLoopDetected",
                    severity: .warning,
                    message: "Video playback iframe player loop detected."
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
            case .network, .accessRequired, .selectorEmpty, .ruleConfiguration, .apiResponseContract, .sourceAPI, .protectedResource, .parserDiagnostics, .unknown:
                return error
            }
        }

        return error
    }

}
