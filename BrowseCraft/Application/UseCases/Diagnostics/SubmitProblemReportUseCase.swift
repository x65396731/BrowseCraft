import BrowseCraftDomain
import BrowseCraftLog
import Foundation

/// 面板交给用例的一份报告草稿（docs/design/Problem-Report-Design.md 第四、六节）。
///
/// 中文注释：`clientReportID` 在面板打开时生成一次，「再试一次」沿用它，服务端按它去重。
/// `targetURL` 与标题是当前列表页、详情页，或 scope 为 content 时目录里那一集的值，由各页从自己的数据里取。
struct ProblemReportDraft: Hashable, Sendable {
    let clientReportID: UUID
    let entry: ProblemReportEntry
    let scope: ProblemReportScope
    let problemType: ProblemReportProblemType
    let note: String
    let screen: DiagnosticScreen
    let source: Source
    let targetURL: String?
    let targetTitle: String?
    let chapterTitle: String?
    let chapterIndex: Int?
    let categoryKey: String?
    let failure: RuleFailureSnapshot?
    let includesLogs: Bool
}

/// 拼报文并发送一份问题报告（合同第六、七节）。只在用户点「发送」时调用（`BCA-OBS-018`）。
struct SubmitProblemReportUseCase: Sendable {
    static let noteMaxCharacters: Int = 500
    static let logWindow: TimeInterval = 10 * 60
    static let logCategories: Set<String> = ["rule", "network", "parse", "image", "screen", "reader", "playback"]
    static let logMaxLines: Int = 300
    static let logMaxBytes: Int = 128 * 1024

    private let submitter: any ProblemReportSubmitting
    private let logProvider: any ProblemReportLogProviding
    private let sourceRepository: any SourceRepository
    private let accessTokenProvider: any PortalAccessTokenProviding
    private let environment: @Sendable () -> ProblemReportEnvironment

    init(
        submitter: any ProblemReportSubmitting,
        logProvider: any ProblemReportLogProviding,
        sourceRepository: any SourceRepository,
        accessTokenProvider: any PortalAccessTokenProviding,
        environment: @escaping @Sendable () -> ProblemReportEnvironment
    ) {
        self.submitter = submitter
        self.logProvider = logProvider
        self.sourceRepository = sourceRepository
        self.accessTokenProvider = accessTokenProvider
        self.environment = environment
    }

    func execute(_ draft: ProblemReportDraft) async throws -> ProblemReportReceipt {
        let clock: ContinuousClock = ContinuousClock()
        let startedAt: ContinuousClock.Instant = clock.now
        let payload: ProblemReportPayload = self.payload(for: draft)
        let accessToken: String? = await self.accessTokenProvider.validAccessToken()
        do {
            let receipt: ProblemReportReceipt = try await self.submitter.submit(payload, accessToken: accessToken)
            AppLog.notice(.diagnostics, "problem-report-submitted", [
                "scope": .enumValue(draft.scope),
                "problemType": .enumValue(draft.problemType),
                "report": .id(receipt.reportID),
                "ms": .duration(clock.now - startedAt)
            ])
            return receipt
        } catch {
            AppLog.error(.diagnostics, "problem-report-failed", [
                "scope": .enumValue(draft.scope),
                "problemType": .enumValue(draft.problemType),
                "ms": .duration(clock.now - startedAt),
                "error": .error(error)
            ])
            throw error
        }
    }

    func payload(for draft: ProblemReportDraft) -> ProblemReportPayload {
        let environment: ProblemReportEnvironment = self.environment()
        let trimmedNote: String = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let logs: [String] = draft.includesLogs
            ? self.logProvider.recentLogLines(
                window: Self.logWindow,
                categories: Self.logCategories,
                maxLines: Self.logMaxLines,
                maxBytes: Self.logMaxBytes
            )
            : []
        return ProblemReportPayload(
            clientReportID: draft.clientReportID,
            entry: draft.entry,
            scope: draft.scope,
            problemType: draft.problemType,
            note: trimmedNote.isEmpty ? nil : String(trimmedNote.prefix(Self.noteMaxCharacters)),
            appVersion: environment.appVersion,
            buildNumber: environment.buildNumber,
            systemVersion: environment.systemVersion,
            deviceModel: environment.deviceModel,
            locale: environment.locale,
            diagnosticCode: environment.diagnosticCode,
            sessionID: environment.sessionID,
            screen: draft.screen.rawValue,
            sourceID: draft.source.id,
            sourceKind: draft.source.diagnosticSourceType.rawValue,
            sourceOrigin: draft.source.origin?.rawValue,
            ruleRevision: self.ruleRevision(sourceID: draft.source.id),
            ruleAppliedAt: draft.source.updatedAt.formatted(.iso8601),
            targetURL: ProblemReportURLSanitizer.clean(draft.targetURL),
            targetTitle: draft.targetTitle,
            chapterTitle: draft.chapterTitle,
            chapterIndex: draft.chapterIndex,
            categoryKey: draft.categoryKey,
            failure: draft.failure,
            logs: logs
        )
    }

    /// 中文注释：规则版本读不到时照样发送，服务端退回按应用时间对版本（`BCA-OBS-022`）。
    private func ruleRevision(sourceID: String) -> String? {
        do {
            return try self.sourceRepository.catalogRevision(sourceID: sourceID)
        } catch {
            AppLog.error(.database, "problem-report-revision-read-failed", ["source": .id(sourceID), "error": .error(error)])
            return nil
        }
    }
}
