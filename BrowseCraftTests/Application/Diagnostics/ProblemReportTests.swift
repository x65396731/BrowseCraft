import BrowseCraftDomain
import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：页内问题报告（docs/design/Problem-Report-Design.md 第五、六节）。
// 网址清洗用例与 PortalCore `tests/problem_reports/test_problem_reports.py` 的 `URL_CASES` 逐条一致。

struct ProblemReportURLSanitizerTests {
    private static let cases: [(raw: String, expected: String?)] = [
        ("https://example.com/vod/12.html?token=abc#t=3", "https://example.com/vod/12.html"),
        ("https://user:pass@example.com:8443/a/b", "https://example.com:8443/a/b"),
        ("https://example.com/play/eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl/1", "https://example.com/play/:token/1"),
        ("https://example.com/token/abc123/chapter/2", "https://example.com/token/:token/chapter/2"),
        ("https://example.com/s/Ab3dEf7hIj9kLm1nOp5qRs2tUv4wXy6z/index.m3u8", "https://example.com/s/:token/index.m3u8"),
        ("https://example.com/comic/0123456789abcdef0123456789abcdef/1.jpg", "https://example.com/comic/0123456789abcdef0123456789abcdef/1.jpg"),
        ("https://example.com/book/abcdefghijklmnopqrstuvwxyzabcdefgh/1", "https://example.com/book/abcdefghijklmnopqrstuvwxyzabcdefgh/1"),
        ("ftp://example.com/a", nil),
        ("not a url", nil),
    ]

    @Test func cleansEveryCaseLikeTheServer() {
        for (raw, expected) in Self.cases {
            #expect(ProblemReportURLSanitizer.clean(raw) == expected, "\(raw)")
        }
    }
}

struct ProblemReportOptionsTests {
    /// `BCA-OBS-021`：每组不超过 9 个，「其他」总在最后。
    @Test func everyGroupHasAtMostNineOptionsEndingWithOther() {
        let kinds: [DiagnosticSourceType] = [.video, .comic, .book]
        for scope in [ProblemReportScope.list, .detail, .content] {
            for kind in kinds {
                for isAudiobook in [false, true] {
                    let options: [ProblemReportProblemType] = ProblemReportOptions.types(scope: scope, kind: kind, isAudiobook: isAudiobook)
                    #expect(options.count <= 9)
                    #expect(options.last == .other)
                    #expect(Set(options).count == options.count)
                }
            }
        }
    }

    /// 合同第五节：30 个问题码都至少出现在一组里。
    @Test func everyProblemTypeIsOfferedSomewhere() {
        var offered: Set<ProblemReportProblemType> = []
        for scope in [ProblemReportScope.list, .detail, .content] {
            for kind in [DiagnosticSourceType.video, .comic, .book] {
                for isAudiobook in [false, true] {
                    offered.formUnion(ProblemReportOptions.types(scope: scope, kind: kind, isAudiobook: isAudiobook))
                }
            }
        }
        #expect(offered == Set(ProblemReportProblemType.allCases))
        #expect(ProblemReportProblemType.allCases.count == 30)
    }
}

struct RuleFailureSnapshotStoreTests {
    @Test func returnsTheLatestSnapshotForPointAndSourceAndKeepsTwenty() {
        let store: RuleFailureSnapshotStore = RuleFailureSnapshotStore()
        for index in 0..<25 {
            store.record(RuleFailureSnapshot(
                error: RuleExecutionError.httpStatus(url: "https://a.test/\(index)", statusCode: 500 + index % 3),
                kind: .network,
                stage: .detail,
                point: index % 2 == 0 ? .comicDetail : .comicReader,
                sourceID: "source-1",
                occurredAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        let latestDetail: RuleFailureSnapshot? = store.latest(points: [.comicDetail], sourceID: "source-1")
        #expect(latestDetail?.occurredAt == Date(timeIntervalSince1970: 24))
        #expect(latestDetail?.errorCase == "httpStatus")
        #expect(latestDetail?.looksSiteSide == true)
        #expect(store.latest(points: [.comicDetail], sourceID: "other") == nil)
    }

    @Test func snapshotNeverCarriesTheURL() {
        let snapshot: RuleFailureSnapshot = RuleFailureSnapshot(
            error: RuleExecutionError.selectorEmpty(stage: .detail, sourceID: "s", url: "https://secret.test/a?token=1", ruleID: "toc"),
            kind: .parse,
            stage: .detail,
            point: .bookDetail,
            sourceID: "s"
        )
        #expect(snapshot.ruleID == "toc")
        #expect(snapshot.summary.contains("secret.test") == false)
        #expect(snapshot.looksSiteSide == false)
    }
}

struct SubmitProblemReportUseCaseTests {
    private final class RecordingSubmitter: ProblemReportSubmitting, @unchecked Sendable {
        private(set) var payloads: [ProblemReportPayload] = []
        private(set) var tokens: [String?] = []

        func submit(_ payload: ProblemReportPayload, accessToken: String?) async throws -> ProblemReportReceipt {
            self.payloads.append(payload)
            self.tokens.append(accessToken)
            return ProblemReportReceipt(reportID: "R-AAAA-BBBB")
        }
    }

    private struct FixedLogs: ProblemReportLogProviding {
        func recentLogLines(window: TimeInterval, categories: Set<String>, maxLines: Int, maxBytes: Int) -> [String] {
            return [#"{"event":"a"}"#]
        }
    }

    private struct NoToken: PortalAccessTokenProviding {
        func validAccessToken() async -> String? {
            return nil
        }
    }

    private final class RevisionRepository: SourceRepository, @unchecked Sendable {
        func fetchSources() throws -> [Source] { return [] }
        func saveSource(_ source: Source) throws {}
        func deleteSource(id: String) throws -> SourceDeletionReceipt? { return nil }
        func restoreDeletedSource(_ receipt: SourceDeletionReceipt) throws {}
        func catalogRevision(sourceID: String) throws -> String? { return "rev-\(sourceID)" }
    }

    private static func source() -> Source {
        let now: Date = Date(timeIntervalSince1970: 100)
        return Source(
            id: "source-1",
            name: "Source",
            baseURL: "https://example.test",
            type: .html,
            configuration: TestSourceFixtures.pluginConfiguration(),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func useCase(submitter: RecordingSubmitter) -> SubmitProblemReportUseCase {
        return SubmitProblemReportUseCase(
            submitter: submitter,
            logProvider: FixedLogs(),
            sourceRepository: RevisionRepository(),
            accessTokenProvider: NoToken(),
            environment: {
                return ProblemReportEnvironment(
                    appVersion: "1.0", buildNumber: "21", systemVersion: "26.0", deviceModel: "iPhone18,1",
                    locale: "zh-Hant", diagnosticCode: "DIAG", sessionID: "S"
                )
            }
        )
    }

    private static func draft(note: String = "  第 3 页之后都是同一张图  ", includesLogs: Bool = true) -> ProblemReportDraft {
        return ProblemReportDraft(
            clientReportID: UUID(),
            entry: .pageMenu,
            scope: .content,
            problemType: .contentMissing,
            note: note,
            screen: .comicDetail,
            source: Self.source(),
            targetURL: "https://example.test/comic/12/3?token=secret#p",
            targetTitle: "Example",
            chapterTitle: "第 3 话",
            chapterIndex: 3,
            categoryKey: nil,
            failure: nil,
            includesLogs: includesLogs
        )
    }

    @Test func payloadCleansURLTrimsNoteAndCarriesRevisionAndLogs() async throws {
        let submitter: RecordingSubmitter = RecordingSubmitter()
        let receipt: ProblemReportReceipt = try await Self.useCase(submitter: submitter).execute(Self.draft())
        let payload: ProblemReportPayload = try #require(submitter.payloads.first)
        #expect(receipt.reportID == "R-AAAA-BBBB")
        #expect(payload.targetURL == "https://example.test/comic/12/3")
        #expect(payload.note == "第 3 页之后都是同一张图")
        #expect(payload.ruleRevision == "rev-source-1")
        #expect(payload.ruleAppliedAt == Date(timeIntervalSince1970: 100).formatted(.iso8601))
        #expect(payload.logs.count == 1)
        #expect(payload.screen == "comic_detail")
        #expect(submitter.tokens == [nil])
    }

    @Test func emptyNoteIsOmittedLongNoteIsCutAndLogsCanBeTurnedOff() {
        let useCase: SubmitProblemReportUseCase = Self.useCase(submitter: RecordingSubmitter())
        #expect(useCase.payload(for: Self.draft(note: "   ")).note == nil)
        let long: String = String(repeating: "字", count: 600)
        #expect(useCase.payload(for: Self.draft(note: long)).note?.count == SubmitProblemReportUseCase.noteMaxCharacters)
        #expect(useCase.payload(for: Self.draft(includesLogs: false)).logs.isEmpty)
    }
}
