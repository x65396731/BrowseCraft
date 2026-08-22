import Foundation
import XCTest
import BrowseCraftCore
@testable import BrowseCraft

final class AssessVideoGenerationInputUseCaseTests: XCTestCase {
    func testUnsafeInputStopsBeforeAnyAcquisition() async {
        let loader: RecordingPreflightPageLoader = RecordingPreflightPageLoader { request in
            return preflightTestPage(request.url)
        }
        let useCase: AssessVideoGenerationInputUseCase = self.makeUseCase(
            publicURLPolicy: RejectingPreflightPublicURLPolicy(),
            httpLoader: loader
        )

        do {
            _ = try await useCase.execute(siteURLString: "https://example.com/root")
            XCTFail("Expected unsafe URL rejection.")
        } catch let issue as VideoGenerationInputPreflightExecutionIssue {
            XCTAssertEqual(issue, .unsafeURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let snapshot: RecordingPreflightPageLoader.Snapshot = await loader.snapshot()
        XCTAssertTrue(snapshot.requests.isEmpty)
    }

    func testAcceptedResultKeepsNormalizedExactInputAsSubmissionURL() async throws {
        let loader: RecordingPreflightPageLoader = RecordingPreflightPageLoader { request in
            return preflightTestPage(request.url)
        }
        let useCase: AssessVideoGenerationInputUseCase = self.makeUseCase(
            httpLoader: loader,
            assessmentMode: .accepted
        )

        let result: VideoGenerationInputPreflight = try await useCase.execute(
            siteURLString: "HTTPS://Example.COM/root?b=2&a=%2Fv#ignored"
        )

        XCTAssertEqual(result.status, .accepted)
        XCTAssertTrue(result.canSubmit)
        XCTAssertEqual(result.submissionString, "https://example.com/root?b=2&a=%2Fv")
        XCTAssertEqual(result.evaluatedInputURL.absoluteString, result.submissionString)
        let snapshot: RecordingPreflightPageLoader.Snapshot = await loader.snapshot()
        XCTAssertEqual(
            snapshot.requests.map(\.url.absoluteString),
            [result.submissionString]
        )
    }

    func testMultipleFamiliesAreRejectedAndCannotSubmit() async throws {
        let loader: RecordingPreflightPageLoader = RecordingPreflightPageLoader { request in
            return preflightTestPage(request.url)
        }
        let useCase: AssessVideoGenerationInputUseCase = self.makeUseCase(
            httpLoader: loader,
            assessmentMode: .multipleFamilies
        )

        let result: VideoGenerationInputPreflight = try await useCase.execute(
            siteURLString: "https://example.com/root"
        )

        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.reason, .multipleIndependentListFamilies)
        XCTAssertFalse(result.canSubmit)
    }

    func testDetailSamplingUsesOneRepresentativePerOwnerAndCapsConcurrency() async throws {
        let loader: RecordingPreflightPageLoader = RecordingPreflightPageLoader { request in
            if request.url.path != "/root" {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            return preflightTestPage(request.url)
        }
        let groups: [SourceListStructuralGroup] = self.publicationGroups(
            ownerCount: 5,
            membersPerOwner: 3
        )
        let useCase: AssessVideoGenerationInputUseCase = self.makeUseCase(
            httpLoader: loader,
            inputGroups: groups,
            assessmentMode: .accepted,
            samplingPolicy: VideoGenerationInputSamplingPolicy(
                maximumConcurrentRequests: 3,
                globalDeadlineSeconds: 2
            )
        )

        let result: VideoGenerationInputPreflight = try await useCase.execute(
            siteURLString: "https://example.com/root"
        )
        let snapshot: RecordingPreflightPageLoader.Snapshot = await loader.snapshot()
        let detailRequests: [PreflightPageRequest] = snapshot.requests.filter { request in
            request.url.path != "/root"
        }

        XCTAssertEqual(result.status, .accepted)
        XCTAssertEqual(result.audit.detailAcquiredRepresentativeCount, 5)
        XCTAssertEqual(detailRequests.count, 5)
        XCTAssertEqual(Set(detailRequests.map(\.url)).count, 5)
        XCTAssertEqual(snapshot.maximumActiveRequestCount, 3)
    }

    func testDetailFailureSamplingUsesAtMostFivePrimaryAndTwoBackups() async throws {
        let loader: RecordingPreflightPageLoader = RecordingPreflightPageLoader { request in
            if request.url.path == "/root" {
                return preflightTestPage(request.url)
            }
            throw PreflightPageAcquisitionError.invalidResponse
        }
        let useCase: AssessVideoGenerationInputUseCase = self.makeUseCase(
            httpLoader: loader,
            inputGroups: self.publicationGroups(ownerCount: 6, membersPerOwner: 3),
            assessmentMode: .accepted
        )

        let result: VideoGenerationInputPreflight = try await useCase.execute(
            siteURLString: "https://example.com/root"
        )
        let snapshot: RecordingPreflightPageLoader.Snapshot = await loader.snapshot()
        let detailRequests: [PreflightPageRequest] = snapshot.requests.filter { request in
            request.url.path != "/root"
        }

        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.reason, .budgetExhausted)
        XCTAssertEqual(result.audit.detailAcquiredRepresentativeCount, 0)
        XCTAssertEqual(detailRequests.count, 7)
        XCTAssertEqual(Set(detailRequests.map(\.url)).count, 7)
    }

    func testGlobalDeadlineReturnsInconclusiveAndCancelsAcquisition() async throws {
        let loader: RecordingPreflightPageLoader = RecordingPreflightPageLoader { _ in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw PreflightPageAcquisitionError.timedOut
        }
        let useCase: AssessVideoGenerationInputUseCase = self.makeUseCase(
            httpLoader: loader,
            samplingPolicy: VideoGenerationInputSamplingPolicy(
                globalDeadlineSeconds: 0.01,
                requestTimeoutSeconds: 60
            )
        )

        let result: VideoGenerationInputPreflight = try await useCase.execute(
            siteURLString: "https://example.com/root"
        )
        let snapshot: RecordingPreflightPageLoader.Snapshot = await loader.snapshot()

        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.reason, .budgetExhausted)
        XCTAssertEqual(result.audit.unresolvedFactCount, 1)
        XCTAssertGreaterThanOrEqual(snapshot.cancellationCount, 1)
    }

    func testCallerCancellationPropagatesAndCancelsAcquisition() async {
        let loader: RecordingPreflightPageLoader = RecordingPreflightPageLoader { _ in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw PreflightPageAcquisitionError.timedOut
        }
        let useCase: AssessVideoGenerationInputUseCase = self.makeUseCase(
            httpLoader: loader,
            samplingPolicy: VideoGenerationInputSamplingPolicy(
                globalDeadlineSeconds: 30,
                requestTimeoutSeconds: 60
            )
        )
        let task: Task<VideoGenerationInputPreflight, Error> = Task {
            return try await useCase.execute(siteURLString: "https://example.com/root")
        }
        for _ in 0..<1_000 {
            if (await loader.snapshot()).requests.isEmpty == false {
                break
            }
            await Task.yield()
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to propagate.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let snapshot: RecordingPreflightPageLoader.Snapshot = await loader.snapshot()
        XCTAssertGreaterThanOrEqual(snapshot.cancellationCount, 1)
    }

    private func makeUseCase(
        publicURLPolicy: any PublicURLChecking = AllowingPreflightPublicURLPolicy(),
        httpLoader: any PreflightPageAcquiring,
        inputGroups: [SourceListStructuralGroup] = [],
        assessmentMode: PreflightTestAssessmentMode = .accepted,
        samplingPolicy: VideoGenerationInputSamplingPolicy = VideoGenerationInputSamplingPolicy()
    ) -> AssessVideoGenerationInputUseCase {
        return AssessVideoGenerationInputUseCase(
            publicURLPolicy: publicURLPolicy,
            httpLoader: httpLoader,
            renderedLoader: UnavailablePreflightRenderedPageLoader(),
            structureObserver: PreflightTestStructureObserver(inputGroups: inputGroups),
            familyAssessor: PreflightTestFamilyAssessor(mode: assessmentMode),
            samplingPolicy: samplingPolicy
        )
    }

    private func publicationGroups(
        ownerCount: Int,
        membersPerOwner: Int
    ) -> [SourceListStructuralGroup] {
        return (1...ownerCount).map { ownerIndex in
            let ownerID: String = "owner-\(ownerIndex)"
            let members: [SourceListStructuralMember] = (1...membersPerOwner).map { memberIndex in
                SourceListStructuralMember(
                    id: "member-\(ownerIndex)-\(memberIndex)",
                    ownerID: ownerID,
                    title: "Video \(ownerIndex)-\(memberIndex)",
                    targetURL: URL(
                        string: "https://example.com/detail/\(ownerIndex)/\(memberIndex)"
                    ),
                    structuralFingerprint: "member-shape-\(ownerIndex)",
                    positionBucket: memberIndex,
                    hasImage: true,
                    linkCount: 1
                )
            }
            return SourceListStructuralGroup(
                id: "group-\(ownerIndex)",
                ownerID: ownerID,
                region: .content,
                ownerFingerprint: "owner-shape-\(ownerIndex)",
                memberShapeFingerprint: "member-shape-\(ownerIndex)",
                familyCompatibilityFingerprint: "family-shape",
                repeatedItemOwner: true,
                titleDetailLinkCommonOwner: true,
                directLogicalChild: true,
                canOwnPublicationItems: true,
                canOwnCollectionChildren: false,
                members: members
            )
        }
    }
}

private actor RecordingPreflightPageLoader: PreflightPageAcquiring {
    struct Snapshot: Sendable {
        let requests: [PreflightPageRequest]
        let maximumActiveRequestCount: Int
        let cancellationCount: Int
    }

    private let handler: @Sendable (PreflightPageRequest) async throws -> PreflightAcquiredPage
    private var requests: [PreflightPageRequest] = []
    private var activeRequestCount: Int = 0
    private var maximumActiveRequestCount: Int = 0
    private var cancellationCount: Int = 0

    init(
        handler: @escaping @Sendable (PreflightPageRequest) async throws -> PreflightAcquiredPage
    ) {
        self.handler = handler
    }

    func acquire(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
        self.requests.append(request)
        self.activeRequestCount += 1
        self.maximumActiveRequestCount = max(
            self.maximumActiveRequestCount,
            self.activeRequestCount
        )
        defer { self.activeRequestCount -= 1 }
        do {
            return try await self.handler(request)
        } catch is CancellationError {
            self.cancellationCount += 1
            throw CancellationError()
        } catch {
            throw error
        }
    }

    func snapshot() -> Snapshot {
        return Snapshot(
            requests: self.requests,
            maximumActiveRequestCount: self.maximumActiveRequestCount,
            cancellationCount: self.cancellationCount
        )
    }
}

private struct AllowingPreflightPublicURLPolicy: PublicURLChecking {
    func validate(_ url: URL) throws {}

    func isSameSite(_ candidate: URL, as inputURL: URL) -> Bool {
        return candidate.host == inputURL.host
    }
}

private struct RejectingPreflightPublicURLPolicy: PublicURLChecking {
    func validate(_ url: URL) throws {
        throw PublicURLCheckError.nonPublicAddress
    }

    func isSameSite(_ candidate: URL, as inputURL: URL) -> Bool {
        return false
    }
}

private struct UnavailablePreflightRenderedPageLoader: PreflightRenderedPageAcquiring {
    @MainActor
    func acquireRendered(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
        throw PreflightPageAcquisitionError.isolationUnavailable
    }
}

private struct PreflightTestStructureObserver: SourceListStructureObserving {
    let inputGroups: [SourceListStructuralGroup]

    func observe(
        document: SourceContentDocument,
        context: SourceListObservationContext
    ) throws -> SourceListStructureObservation {
        let isInput: Bool = context.purpose == .exactInput
        return SourceListStructureObservation(
            documentIdentity: context.documentIdentity,
            acquisitionIdentity: context.acquisitionIdentity,
            finalURL: document.finalURL,
            purpose: context.purpose,
            lineage: context.lineage,
            documentShape: SourceListDocumentShape(
                kind: isInput ? .directListCandidate : .detail,
                fingerprint: isInput ? "input-shape" : "detail-shape",
                repeatedOwnerCount: isInput ? self.inputGroups.count : 0,
                contentLinkCount: isInput
                    ? self.inputGroups.reduce(0) { $0 + $1.members.count }
                    : 0,
                textLengthBucket: 2
            ),
            groups: isInput ? self.inputGroups : [],
            issues: []
        )
    }
}

private enum PreflightTestAssessmentMode: Sendable {
    case accepted
    case multipleFamilies
}

private struct PreflightTestFamilyAssessor: SourceListFamilyAssessing {
    let mode: PreflightTestAssessmentMode

    func assess(_ input: SourceListFamilyAssessmentInput) -> SourceListFamilyAssessment {
        let documentIdentity: String = input.inputObservation.documentIdentity
        switch self.mode {
        case .accepted:
            let unit: SourceListPublicationUnit = SourceListPublicationUnit(
                id: "unit-1",
                documentIdentity: documentIdentity,
                ownerID: "owner-1",
                disposition: .qualified
            )
            return SourceListFamilyAssessment(
                entryShapeFacts: SourceListEntryShapeFacts(
                    directPublicationUnitIDs: [unit.id]
                ),
                requiredPublicationUnits: [unit],
                families: [
                    SourceListFamilyCoverage(
                        familyID: "family-1",
                        coveredPublicationUnitIDs: [unit.id],
                        supportingObservationIdentities: [documentIdentity]
                    )
                ],
                redundantObservations: [],
                unresolvedFacts: []
            )
        case .multipleFamilies:
            let units: [SourceListPublicationUnit] = ["unit-1", "unit-2"].map { unitID in
                SourceListPublicationUnit(
                    id: unitID,
                    documentIdentity: documentIdentity,
                    ownerID: "owner-" + unitID,
                    disposition: .qualified
                )
            }
            return SourceListFamilyAssessment(
                entryShapeFacts: SourceListEntryShapeFacts(
                    directPublicationUnitIDs: units.map(\.id)
                ),
                requiredPublicationUnits: units,
                families: units.map { unit in
                    SourceListFamilyCoverage(
                        familyID: "family-" + unit.id,
                        coveredPublicationUnitIDs: [unit.id],
                        supportingObservationIdentities: [documentIdentity]
                    )
                },
                redundantObservations: [],
                unresolvedFacts: []
            )
        }
    }
}

private func preflightTestPage(_ url: URL) -> PreflightAcquiredPage {
    let html: String = "<html><body><main>Usable list page with stable test evidence.</main></body></html>"
    return PreflightAcquiredPage(
        requestedURL: url,
        data: Data(html.utf8),
        finalURL: url,
        statusCode: 200,
        mediaType: "text/html",
        textEncodingName: "utf-8",
        acquisitionIdentity: "test-" + url.absoluteString,
        source: .http,
        isolationScope: .fullHTTP
    )
}
