import Foundation
import BrowseCraftCore

typealias VideoGenerationInputProgressHandler = @MainActor @Sendable (
    VideoGenerationInputPreflightProgress
) -> Void

/// v3（`BC-PREFLIGHT` §5 / §7 / §8.1）：只采集输入 URL 这一份文档，判断它是否恰好承载一个 List family。
struct AssessVideoGenerationInputUseCase: Sendable {
    private struct DeadlineReached: Error, Sendable {}

    private enum EvidenceIssue: Error, Sendable {
        case antiBotChallenge
        case requiresUserSession
        case isolationUnavailable
    }

    private let normalizer: VideoGenerationInputURLNormalizer
    private let publicURLPolicy: any PublicURLChecking
    private let httpLoader: any PreflightPageAcquiring
    private let renderedLoader: any PreflightRenderedPageAcquiring
    private let pageClassifier: VideoPreflightPageClassifier
    private let structureObserver: any SourceListStructureObserving
    private let entryFamilyAssessor: any SourceListEntryFamilyAssessing
    private let reducer: VideoGenerationInputReducer
    private let samplingPolicy: VideoGenerationInputSamplingPolicy
    private let identityGenerator: @Sendable () -> String
    /// 中文注释：只供特征化测试读取观测与归约事实，不参与判定、不进产物。
    private let assessmentObserver: (@Sendable (SourceListStructureObservation, SourceListEntryFamilyAssessment) -> Void)?

    init(
        normalizer: VideoGenerationInputURLNormalizer = VideoGenerationInputURLNormalizer(),
        publicURLPolicy: any PublicURLChecking,
        httpLoader: any PreflightPageAcquiring,
        renderedLoader: any PreflightRenderedPageAcquiring,
        pageClassifier: VideoPreflightPageClassifier = VideoPreflightPageClassifier(),
        structureObserver: any SourceListStructureObserving,
        entryFamilyAssessor: any SourceListEntryFamilyAssessing,
        reducer: VideoGenerationInputReducer = VideoGenerationInputReducer(),
        samplingPolicy: VideoGenerationInputSamplingPolicy = VideoGenerationInputSamplingPolicy(),
        identityGenerator: @escaping @Sendable () -> String = { UUID().uuidString },
        assessmentObserver: (@Sendable (SourceListStructureObservation, SourceListEntryFamilyAssessment) -> Void)? = nil
    ) {
        self.normalizer = normalizer
        self.publicURLPolicy = publicURLPolicy
        self.httpLoader = httpLoader
        self.renderedLoader = renderedLoader
        self.pageClassifier = pageClassifier
        self.structureObserver = structureObserver
        self.entryFamilyAssessor = entryFamilyAssessor
        self.reducer = reducer
        self.samplingPolicy = samplingPolicy
        self.identityGenerator = identityGenerator
        self.assessmentObserver = assessmentObserver
    }

    func execute(
        siteURLString: String,
        progress: VideoGenerationInputProgressHandler? = nil
    ) async throws -> VideoGenerationInputPreflight {
        await progress?(.validatingInput)
        let inputURL: VideoGenerationInputURL = try self.normalizer.normalize(siteURLString)
        do {
            try self.publicURLPolicy.validate(inputURL.evaluatedURL)
        } catch {
            throw VideoGenerationInputPreflightExecutionIssue.unsafeURL
        }

        do {
            return try await self.withDeadline {
                try await self.performAssessment(inputURL: inputURL, progress: progress)
            }
        } catch is DeadlineReached {
            return self.reducer.reduce(
                VideoGenerationInputReducerInput(
                    inputURL: inputURL,
                    entryShape: .ambiguous,
                    acquisitionState: .available,
                    budgetExhausted: true,
                    audit: VideoGenerationInputPreflightAudit()
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        }
    }

    private func performAssessment(
        inputURL: VideoGenerationInputURL,
        progress: VideoGenerationInputProgressHandler?
    ) async throws -> VideoGenerationInputPreflight {
        await progress?(.acquiringInput)
        let startedAt: Date = Date()
        let inputPage: PreflightAcquiredPage
        do {
            inputPage = try await self.acquireUsablePage(inputURL.evaluatedURL)
        } catch let issue as EvidenceIssue {
            return self.earlyEvidenceResult(issue: issue, inputURL: inputURL)
        }
        let acquiredAt: Date = Date()

        await progress?(.observingEntryShape)
        let identity: String = self.identityGenerator()
        let observation: SourceListStructureObservation = try self.structureObserver.observe(
            document: self.sourceDocument(from: inputPage),
            context: SourceListObservationContext(
                documentIdentity: "input:" + identity,
                acquisitionIdentity: inputPage.acquisitionIdentity,
                purpose: .exactInput
            )
        )
        let observedAt: Date = Date()

        await progress?(.reducingResult)
        let assessment: SourceListEntryFamilyAssessment = self.entryFamilyAssessor.assess(observation)
        self.assessmentObserver?(observation, assessment)
        // 中文注释：只记耗时与计数（`BC-PREFLIGHT-042`：不记 URL 正文、Cookie、selector）。
        AppLog.notice(
            .discovery,
            event: "video-preflight-timing",
            metadata: [
                "acquireMs": String(Int(acquiredAt.timeIntervalSince(startedAt) * 1000)),
                "observeMs": String(Int(observedAt.timeIntervalSince(acquiredAt) * 1000)),
                "reduceMs": String(Int(Date().timeIntervalSince(observedAt) * 1000)),
                "bytes": String(inputPage.byteCount),
                "source": inputPage.source.rawValue,
                "groups": String(observation.groups.count),
                "families": String(assessment.familyCount)
            ]
        )

        // 中文注释：截断只在截掉了内容区域时才是 ambiguous（§7.4）——有主列表即视为内容区域已观测到。
        let truncatedContent: Bool = assessment.scanTruncated && assessment.mainListGroupID == nil
        let entryShape: VideoGenerationEntryShape
        if truncatedContent {
            entryShape = .ambiguous
        } else {
            switch assessment.familyCount {
            case 0:
                entryShape = .noListFamily
            case 1:
                entryShape = .directListOwner
            default:
                entryShape = .multipleListFamilies
            }
        }
        return self.reducer.reduce(
            VideoGenerationInputReducerInput(
                inputURL: inputURL,
                entryShape: entryShape,
                acquisitionState: .available,
                budgetExhausted: false,
                audit: VideoGenerationInputPreflightAudit(
                    inputAcquisitionCount: 1,
                    publicationGroupCount: assessment.publicationGroupIDs.count,
                    listCount: assessment.listGroupIDs.count,
                    familyCount: assessment.familyCount,
                    scanTruncated: assessment.scanTruncated
                )
            )
        )
    }

    private func acquireUsablePage(_ url: URL) async throws -> PreflightAcquiredPage {
        let request: PreflightPageRequest = PreflightPageRequest(
            url: url,
            timeoutSeconds: self.samplingPolicy.requestTimeoutSeconds
        )
        let httpPage: PreflightAcquiredPage
        do {
            httpPage = try await self.httpLoader.acquire(request)
        } catch let acquisitionError as PreflightPageAcquisitionError {
            switch acquisitionError {
            case .authenticationRequired:
                throw EvidenceIssue.requiresUserSession
            case .unsafeRedirect:
                throw VideoGenerationInputPreflightExecutionIssue.unsafeURL
            default:
                throw acquisitionError
            }
        }
        switch self.pageClassifier.classify(httpPage) {
        case .usableHTML:
            return httpPage
        case .technicalShell:
            do {
                let renderedPage: PreflightAcquiredPage = try await self.renderedLoader
                    .acquireRendered(request)
                switch self.pageClassifier.classify(renderedPage) {
                case .usableHTML:
                    return renderedPage
                case .antiBotChallenge:
                    throw EvidenceIssue.antiBotChallenge
                case .requiresUserSession:
                    throw EvidenceIssue.requiresUserSession
                case .technicalShell, .unsupportedContent:
                    throw EvidenceIssue.isolationUnavailable
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let issue as EvidenceIssue {
                throw issue
            } catch let acquisitionError as PreflightPageAcquisitionError {
                switch acquisitionError {
                case .authenticationRequired:
                    throw EvidenceIssue.requiresUserSession
                case .unsafeRedirect:
                    throw VideoGenerationInputPreflightExecutionIssue.unsafeURL
                default:
                    throw EvidenceIssue.isolationUnavailable
                }
            } catch {
                throw EvidenceIssue.isolationUnavailable
            }
        case .antiBotChallenge:
            throw EvidenceIssue.antiBotChallenge
        case .requiresUserSession:
            throw EvidenceIssue.requiresUserSession
        case .unsupportedContent:
            throw VideoGenerationInputPreflightExecutionIssue.unsupportedContent
        }
    }

    private func sourceDocument(from page: PreflightAcquiredPage) -> SourceContentDocument {
        return SourceContentDocument(
            data: page.data,
            finalURL: page.finalURL,
            format: .html,
            mediaType: page.mediaType,
            textEncodingName: page.textEncodingName
        )
    }

    private func earlyEvidenceResult(
        issue: EvidenceIssue,
        inputURL: VideoGenerationInputURL
    ) -> VideoGenerationInputPreflight {
        let state: VideoGenerationPreflightAcquisitionState
        switch issue {
        case .antiBotChallenge:
            state = .antiBotChallenge
        case .requiresUserSession:
            state = .requiresUserSession
        case .isolationUnavailable:
            state = .isolationUnavailable
        }
        return self.reducer.reduce(
            VideoGenerationInputReducerInput(
                inputURL: inputURL,
                entryShape: .ambiguous,
                acquisitionState: state,
                budgetExhausted: false,
                audit: VideoGenerationInputPreflightAudit()
            )
        )
    }

    private func withDeadline(
        operation: @escaping @Sendable () async throws -> VideoGenerationInputPreflight
    ) async throws -> VideoGenerationInputPreflight {
        return try await withThrowingTaskGroup(of: VideoGenerationInputPreflight.self) { group in
            defer { group.cancelAll() }
            group.addTask {
                return try await operation()
            }
            let deadlineSeconds: TimeInterval = self.samplingPolicy.globalDeadlineSeconds
            group.addTask {
                let nanoseconds: UInt64 = UInt64(max(deadlineSeconds, 0.001) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw DeadlineReached()
            }
            guard let first: VideoGenerationInputPreflight = try await group.next() else {
                throw DeadlineReached()
            }
            return first
        }
    }
}
