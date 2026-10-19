import BrowseCraftAPIKit
import Foundation

/// `ProblemReportSubmitting` 的 PortalCore 适配器（docs/design/Problem-Report-Design.md 第七、九节）。
///
/// 中文注释：服务端错误只分两类给界面——429 的 `PROBLEM_REPORT_RATE_LIMITED` 为「太频繁」，其余为「发送失败」。
/// 取消原样抛出，由调用方当作没发送。
struct APIKitProblemReportClient: ProblemReportSubmitting {
    private let api: PortalProblemReportAPI

    init(api: PortalProblemReportAPI) {
        self.api = api
    }

    func submit(_ payload: ProblemReportPayload, accessToken: String?) async throws -> ProblemReportReceipt {
        do {
            let response: PortalProblemReportResponse = try await self.api.submit(
                Self.request(from: payload),
                accessToken: accessToken
            )
            return ProblemReportReceipt(reportID: response.reportId)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PortalAPIError {
            if case .server(let statusCode, let body) = error,
               statusCode == 429 || body.code == PortalProblemReportErrorCode.rateLimited {
                throw ProblemReportSubmissionError.rateLimited
            }
            throw ProblemReportSubmissionError.failed
        } catch {
            throw ProblemReportSubmissionError.failed
        }
    }

    private static func request(from payload: ProblemReportPayload) -> PortalProblemReportRequest {
        return PortalProblemReportRequest(
            clientReportId: payload.clientReportID.uuidString,
            entry: payload.entry.rawValue,
            scope: payload.scope.rawValue,
            problemType: payload.problemType.rawValue,
            note: payload.note,
            appVersion: payload.appVersion,
            buildNumber: payload.buildNumber,
            systemVersion: payload.systemVersion,
            deviceModel: payload.deviceModel,
            locale: payload.locale,
            diagnosticCode: payload.diagnosticCode,
            sessionId: payload.sessionID,
            screen: payload.screen,
            sourceId: payload.sourceID,
            sourceKind: payload.sourceKind,
            sourceOrigin: payload.sourceOrigin,
            ruleRevision: payload.ruleRevision,
            ruleAppliedAt: payload.ruleAppliedAt,
            targetURL: payload.targetURL,
            targetTitle: payload.targetTitle,
            chapterTitle: payload.chapterTitle,
            chapterIndex: payload.chapterIndex,
            categoryKey: payload.categoryKey,
            failure: payload.failure.map { snapshot in
                return PortalProblemReportFailure(
                    point: snapshot.point.rawValue,
                    stage: snapshot.stage,
                    kind: snapshot.kind,
                    errorCase: snapshot.errorCase,
                    statusCode: snapshot.statusCode,
                    ruleId: snapshot.ruleID,
                    operation: snapshot.operation,
                    selector: snapshot.selector,
                    summary: snapshot.summary,
                    occurredAt: snapshot.occurredAt.formatted(.iso8601)
                )
            },
            logs: payload.logs
        )
    }
}
