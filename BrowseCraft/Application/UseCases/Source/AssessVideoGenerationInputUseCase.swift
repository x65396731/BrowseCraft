import Foundation
import BrowseCraftCore

typealias VideoGenerationInputProgressHandler = @MainActor @Sendable (
    VideoGenerationInputPreflightProgress
) -> Void

struct AssessVideoGenerationInputUseCase: Sendable {
    private struct DeadlineReached: Error, Sendable {}

    private enum EvidenceIssue: Error, Sendable {
        case antiBotChallenge
        case requiresUserSession
        case isolationUnavailable
    }

    private struct AcquiredOneHopPage: Sendable {
        let work: VideoGenerationOneHopWorkDescriptor
        let page: PreflightAcquiredPage
    }

    private struct DetailWorkDescriptor: Hashable, Sendable {
        let parentDocumentIdentity: String
        let ownerID: String
        let memberID: String
        let structuralGroupID: String
        let url: URL

        var ownerKey: String {
            return self.parentDocumentIdentity + "|" + self.ownerID + "|" + self.structuralGroupID
        }
    }

    private struct SampleAcquisition<Work: Sendable>: Sendable {
        let primary: Work
        let selected: Work?
        let page: PreflightAcquiredPage?
        let evidenceIssues: [EvidenceIssue]
    }

    private struct IndexedValue<Value: Sendable>: Sendable {
        let index: Int
        let value: Value
    }

    private let normalizer: VideoGenerationInputURLNormalizer
    private let publicURLPolicy: any PublicURLChecking
    private let httpLoader: any PreflightPageAcquiring
    private let renderedLoader: any PreflightRenderedPageAcquiring
    private let pageClassifier: VideoPreflightPageClassifier
    private let structureObserver: any SourceListStructureObserving
    private let familyAssessor: any SourceListFamilyAssessing
    private let oneHopPlanner: VideoGenerationOneHopPlanner
    private let capabilityPolicy: VideoGenerationCapabilityPolicy
    private let reducer: VideoGenerationInputReducer
    private let samplingPolicy: VideoGenerationInputSamplingPolicy
    private let identityGenerator: @Sendable () -> String
    /// 中文注释：只供特征化测试读取归约事实（fact code 直方图），不参与判定、不进产物。
    private let assessmentObserver: (@Sendable (SourceListFamilyAssessmentInput, SourceListFamilyAssessment) -> Void)?

    init(
        normalizer: VideoGenerationInputURLNormalizer = VideoGenerationInputURLNormalizer(),
        publicURLPolicy: any PublicURLChecking,
        httpLoader: any PreflightPageAcquiring,
        renderedLoader: any PreflightRenderedPageAcquiring,
        pageClassifier: VideoPreflightPageClassifier = VideoPreflightPageClassifier(),
        structureObserver: any SourceListStructureObserving,
        familyAssessor: any SourceListFamilyAssessing,
        oneHopPlanner: VideoGenerationOneHopPlanner = VideoGenerationOneHopPlanner(),
        capabilityPolicy: VideoGenerationCapabilityPolicy = VideoGenerationCapabilityPolicy(),
        reducer: VideoGenerationInputReducer = VideoGenerationInputReducer(),
        samplingPolicy: VideoGenerationInputSamplingPolicy = VideoGenerationInputSamplingPolicy(),
        identityGenerator: @escaping @Sendable () -> String = { UUID().uuidString },
        assessmentObserver: (@Sendable (SourceListFamilyAssessmentInput, SourceListFamilyAssessment) -> Void)? = nil
    ) {
        self.assessmentObserver = assessmentObserver
        self.normalizer = normalizer
        self.publicURLPolicy = publicURLPolicy
        self.httpLoader = httpLoader
        self.renderedLoader = renderedLoader
        self.pageClassifier = pageClassifier
        self.structureObserver = structureObserver
        self.familyAssessor = familyAssessor
        self.oneHopPlanner = oneHopPlanner
        self.capabilityPolicy = capabilityPolicy
        self.reducer = reducer
        self.samplingPolicy = samplingPolicy
        self.identityGenerator = identityGenerator
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
                    familyCoverageState: .unresolved,
                    acquisitionState: .available,
                    budgetExhausted: true,
                    audit: VideoGenerationInputPreflightAudit(unresolvedFactCount: 1)
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
        let inputPage: PreflightAcquiredPage
        do {
            inputPage = try await self.acquireUsablePage(inputURL.evaluatedURL)
        } catch let issue as EvidenceIssue {
            return self.earlyEvidenceResult(issue: issue, inputURL: inputURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch let executionIssue as VideoGenerationInputPreflightExecutionIssue {
            throw executionIssue
        } catch {
            throw VideoGenerationInputPreflightExecutionIssue.requestFailed
        }

        await progress?(.observingEntryShape)
        let inputDocumentIdentity: String = "input-" + self.identityGenerator()
        let inputObservation: SourceListStructureObservation = try self.structureObserver.observe(
            document: self.sourceDocument(from: inputPage),
            context: SourceListObservationContext(
                documentIdentity: inputDocumentIdentity,
                acquisitionIdentity: inputPage.acquisitionIdentity,
                purpose: .exactInput
            )
        )
        let decisions: [VideoGenerationOneHopURLDecision] = self.oneHopDecisions(
            observation: inputObservation,
            inputURL: inputURL.evaluatedURL
        )
        let plan: VideoGenerationOneHopPlan = self.oneHopPlanner.plan(
            observation: inputObservation,
            decisions: decisions
        )

        var acquiredPageByURL: [URL: PreflightAcquiredPage] = [
            inputURL.evaluatedURL: inputPage
        ]
        acquiredPageByURL[inputPage.finalURL] = inputPage
        var missingObservations: [SourceListMissingObservation] = []
        var acquisitionState: VideoGenerationPreflightAcquisitionState = .available
        var acquiredOneHopPages: [AcquiredOneHopPage] = []
        let backupByGroup: [String: VideoGenerationOneHopWorkDescriptor] = Dictionary(
            uniqueKeysWithValues: plan.backups.map { backup in
                (backup.structuralGroupID, backup)
            }
        )

        var backupForPrimaryMemberID: [String: VideoGenerationOneHopWorkDescriptor] = [:]
        for primary: VideoGenerationOneHopWorkDescriptor in plan.primary {
            guard backupForPrimaryMemberID.values.contains(where: { backup in
                backup.structuralGroupID == primary.structuralGroupID
            }) == false, let backup: VideoGenerationOneHopWorkDescriptor = backupByGroup[
                primary.structuralGroupID
            ] else {
                continue
            }
            backupForPrimaryMemberID[primary.memberID] = backup
        }
        let oneHopBackupAssignments: [String: VideoGenerationOneHopWorkDescriptor] =
            backupForPrimaryMemberID
        await progress?(
            .checkingOneHop(
                completed: 0,
                budget: self.samplingPolicy.maximumOneHopPrimary
            )
        )
        let oneHopAcquisitions: [SampleAcquisition<VideoGenerationOneHopWorkDescriptor>] =
            try await self.boundedMap(
                plan.primary,
                maximumConcurrent: self.samplingPolicy.maximumConcurrentRequests,
                progress: { completed in
                    await progress?(
                        .checkingOneHop(
                            completed: completed,
                            budget: self.samplingPolicy.maximumOneHopPrimary
                        )
                    )
                },
                operation: { primary in
                    try await self.acquireOneHopSample(
                        primary: primary,
                        backup: oneHopBackupAssignments[primary.memberID]
                    )
                }
            )
        for acquisition: SampleAcquisition<VideoGenerationOneHopWorkDescriptor> in oneHopAcquisitions {
            for issue: EvidenceIssue in acquisition.evidenceIssues {
                acquisitionState = self.mergedAcquisitionState(acquisitionState, issue: issue)
            }
            if let selected: VideoGenerationOneHopWorkDescriptor = acquisition.selected,
               let page: PreflightAcquiredPage = acquisition.page {
                acquiredPageByURL[selected.url] = page
                acquiredPageByURL[page.finalURL] = page
                acquiredOneHopPages.append(AcquiredOneHopPage(work: selected, page: page))
            } else {
                missingObservations.append(
                    SourceListMissingObservation(
                        kind: .oneHopChild,
                        parentDocumentIdentity: inputObservation.documentIdentity,
                        parentOwnerID: acquisition.primary.ownerID,
                        parentMemberID: acquisition.primary.memberID,
                        reason: .acquisitionFailed
                    )
                )
            }
        }

        let acquiredOneHopMemberIDs: Set<String> = Set(acquiredOneHopPages.map(\.work.memberID))
        for group: SourceListStructuralGroup in inputObservation.groups
        where group.region == .content
            && group.nestedGroupIDs.isEmpty
            && group.directLogicalChild
            && group.canOwnCollectionChildren
            && group.members.count >= 2 {
            for member: SourceListStructuralMember in group.members
            where acquiredOneHopMemberIDs.contains(member.id) == false {
                missingObservations.append(
                    SourceListMissingObservation(
                        kind: .oneHopChild,
                        parentDocumentIdentity: inputObservation.documentIdentity,
                        parentOwnerID: group.ownerID,
                        parentMemberID: member.id,
                        reason: .notSelected
                    )
                )
            }
        }

        var oneHopObservations: [SourceListLinkedObservation] = []
        var detailObservations: [SourceListLinkedObservation] = []
        for acquired: AcquiredOneHopPage in acquiredOneHopPages {
            let lineage: SourceListObservationLineage = SourceListObservationLineage(
                parentDocumentIdentity: inputObservation.documentIdentity,
                parentOwnerID: acquired.work.ownerID,
                parentMemberID: acquired.work.memberID
            )
            let document: SourceContentDocument = self.sourceDocument(from: acquired.page)
            let childObservation: SourceListStructureObservation = try self.structureObserver.observe(
                document: document,
                context: SourceListObservationContext(
                    documentIdentity: "one-hop-" + self.identityGenerator(),
                    acquisitionIdentity: acquired.page.acquisitionIdentity,
                    purpose: .oneHopChild,
                    lineage: lineage
                )
            )
            oneHopObservations.append(
                SourceListLinkedObservation(
                    parentDocumentIdentity: inputObservation.documentIdentity,
                    parentOwnerID: acquired.work.ownerID,
                    parentMemberID: acquired.work.memberID,
                    observation: childObservation
                )
            )
            let directDetailObservation: SourceListStructureObservation = try self.structureObserver.observe(
                document: document,
                context: SourceListObservationContext(
                    documentIdentity: "detail-reuse-" + self.identityGenerator(),
                    acquisitionIdentity: acquired.page.acquisitionIdentity,
                    purpose: .detailSample,
                    lineage: lineage
                )
            )
            detailObservations.append(
                SourceListLinkedObservation(
                    parentDocumentIdentity: inputObservation.documentIdentity,
                    parentOwnerID: acquired.work.ownerID,
                    parentMemberID: acquired.work.memberID,
                    observation: directDetailObservation
                )
            )
        }

        let detailPlan: (primary: [DetailWorkDescriptor], backups: [String: DetailWorkDescriptor], representedMembers: Set<String>, totalOwnerCount: Int) = self.detailPlan(
            inputObservation: inputObservation,
            oneHopObservations: oneHopObservations
        )
        let cachedPages: [URL: PreflightAcquiredPage] = acquiredPageByURL
        await progress?(
            .samplingDetails(
                completed: 0,
                budget: self.samplingPolicy.maximumDetailPrimary
            )
        )
        let detailAcquisitions: [SampleAcquisition<DetailWorkDescriptor>] =
            try await self.boundedMap(
                detailPlan.primary,
                maximumConcurrent: self.samplingPolicy.maximumConcurrentRequests,
                progress: { completed in
                    await progress?(
                        .samplingDetails(
                            completed: completed,
                            budget: self.samplingPolicy.maximumDetailPrimary
                        )
                    )
                },
                operation: { primary in
                    try await self.acquireDetailSample(
                        primary: primary,
                        backup: detailPlan.backups[primary.ownerKey],
                        cachedPages: cachedPages
                    )
                }
            )
        var detailCompleted: Int = 0
        for acquisition: SampleAcquisition<DetailWorkDescriptor> in detailAcquisitions {
            for issue: EvidenceIssue in acquisition.evidenceIssues {
                acquisitionState = self.mergedAcquisitionState(acquisitionState, issue: issue)
            }
            guard let selectedWork: DetailWorkDescriptor = acquisition.selected,
                  let page: PreflightAcquiredPage = acquisition.page else {
                missingObservations.append(
                    self.missingDetail(acquisition.primary, reason: .acquisitionFailed)
                )
                continue
            }
            acquiredPageByURL[selectedWork.url] = page
            acquiredPageByURL[page.finalURL] = page
            let detailObservation: SourceListStructureObservation = try self.structureObserver.observe(
                document: self.sourceDocument(from: page),
                context: SourceListObservationContext(
                    documentIdentity: "detail-" + self.identityGenerator(),
                    acquisitionIdentity: page.acquisitionIdentity,
                    purpose: .detailSample,
                    lineage: SourceListObservationLineage(
                        parentDocumentIdentity: selectedWork.parentDocumentIdentity,
                        parentOwnerID: selectedWork.ownerID,
                        parentMemberID: selectedWork.memberID
                    )
                )
            )
            detailObservations.append(
                SourceListLinkedObservation(
                    parentDocumentIdentity: selectedWork.parentDocumentIdentity,
                    parentOwnerID: selectedWork.ownerID,
                    parentMemberID: selectedWork.memberID,
                    observation: detailObservation
                )
            )
            detailCompleted += 1
        }

        for work: DetailWorkDescriptor in self.allDetailWork(
            inputObservation: inputObservation,
            oneHopObservations: oneHopObservations
        ) where detailPlan.representedMembers.contains(work.memberID) == false {
            missingObservations.append(self.missingDetail(work, reason: .notSelected))
        }

        await progress?(.reducingResult)
        let assessmentInput: SourceListFamilyAssessmentInput = SourceListFamilyAssessmentInput(
            inputObservation: inputObservation,
            oneHopObservations: oneHopObservations,
            detailObservations: detailObservations,
            missingObservations: missingObservations
        )
        let assessment: SourceListFamilyAssessment = self.familyAssessor.assess(assessmentInput)
        self.assessmentObserver?(assessmentInput, assessment)
        let entryShape: VideoGenerationEntryShape = self.capabilityPolicy.entryShape(
            from: assessment
        )
        let familyCoverage: VideoGenerationFamilyCoverageState = self.capabilityPolicy
            .familyCoverageState(from: assessment)
        let qualifiedLeafCount: Int = oneHopObservations.filter { linkedObservation in
            linkedObservation.observation.documentShape.kind == .leafList
        }.count
        // 中文注释：设计书 §7.4——「达到预算**且**未决结果可能改变 entry shape 或 single-family 结论」才是
        // budgetExhausted；只超预算而未采样成员已被同 owner 代表闭合（Core 不出 unresolved）时不算。
        let budgetReached: Bool = plan.observedGroupCount
            > self.samplingPolicy.maximumOneHopPrimary
            || detailPlan.totalOwnerCount > self.samplingPolicy.maximumDetailPrimary
        let budgetSensitiveFacts: Bool = assessment.unresolvedFacts.contains { fact in
            switch fact.code {
            case .budgetLimited, .oneHopMemberUnobserved, .detailCompatibilityUnobserved:
                return true
            case .oneHopMemberConflicting, .detailCompatibilityConflicting, .familyIdentityUnresolved,
                 .publicationIdentityUnresolved, .acquisitionFailed, .isolationUnavailable,
                 .entryShapeAmbiguous:
                return false
            }
        }
        let budgetExhausted: Bool = budgetReached && budgetSensitiveFacts
        let audit: VideoGenerationInputPreflightAudit = VideoGenerationInputPreflightAudit(
            oneHopObservedGroupCount: plan.observedGroupCount,
            oneHopAcquiredRepresentativeCount: acquiredOneHopPages.count,
            oneHopQualifiedLeafCount: qualifiedLeafCount,
            detailAcquiredRepresentativeCount: detailCompleted,
            unresolvedFactCount: assessment.unresolvedFacts.count
        )
        return self.reducer.reduce(
            VideoGenerationInputReducerInput(
                inputURL: inputURL,
                entryShape: entryShape,
                familyCoverageState: familyCoverage,
                acquisitionState: acquisitionState,
                budgetExhausted: budgetExhausted,
                audit: audit
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

    private func acquireOneHopSample(
        primary: VideoGenerationOneHopWorkDescriptor,
        backup: VideoGenerationOneHopWorkDescriptor?
    ) async throws -> SampleAcquisition<VideoGenerationOneHopWorkDescriptor> {
        var evidenceIssues: [EvidenceIssue] = []
        do {
            let page: PreflightAcquiredPage = try await self.acquireUsablePage(primary.url)
            return SampleAcquisition(
                primary: primary,
                selected: primary,
                page: page,
                evidenceIssues: evidenceIssues
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let issue as EvidenceIssue {
            evidenceIssues.append(issue)
        } catch {
            // A backup is allowed for any primary acquisition failure.
        }

        guard let backup: VideoGenerationOneHopWorkDescriptor = backup else {
            return SampleAcquisition(
                primary: primary,
                selected: nil,
                page: nil,
                evidenceIssues: evidenceIssues
            )
        }
        do {
            let page: PreflightAcquiredPage = try await self.acquireUsablePage(backup.url)
            return SampleAcquisition(
                primary: primary,
                selected: backup,
                page: page,
                evidenceIssues: []
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let issue as EvidenceIssue {
            evidenceIssues.append(issue)
        } catch {
            // Missing evidence is returned below and remains fail-closed.
        }
        return SampleAcquisition(
            primary: primary,
            selected: nil,
            page: nil,
            evidenceIssues: evidenceIssues
        )
    }

    private func acquireDetailSample(
        primary: DetailWorkDescriptor,
        backup: DetailWorkDescriptor?,
        cachedPages: [URL: PreflightAcquiredPage]
    ) async throws -> SampleAcquisition<DetailWorkDescriptor> {
        var evidenceIssues: [EvidenceIssue] = []
        do {
            let page: PreflightAcquiredPage
            if let cachedPage: PreflightAcquiredPage = cachedPages[primary.url] {
                page = cachedPage
            } else {
                page = try await self.acquireUsablePage(primary.url)
            }
            return SampleAcquisition(
                primary: primary,
                selected: primary,
                page: page,
                evidenceIssues: evidenceIssues
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let issue as EvidenceIssue {
            evidenceIssues.append(issue)
        } catch {
            // A backup is allowed for any primary acquisition failure.
        }

        guard let backup: DetailWorkDescriptor = backup else {
            return SampleAcquisition(
                primary: primary,
                selected: nil,
                page: nil,
                evidenceIssues: evidenceIssues
            )
        }
        do {
            let page: PreflightAcquiredPage
            if let cachedPage: PreflightAcquiredPage = cachedPages[backup.url] {
                page = cachedPage
            } else {
                page = try await self.acquireUsablePage(backup.url)
            }
            return SampleAcquisition(
                primary: primary,
                selected: backup,
                page: page,
                evidenceIssues: []
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let issue as EvidenceIssue {
            evidenceIssues.append(issue)
        } catch {
            // Missing evidence is returned below and remains fail-closed.
        }
        return SampleAcquisition(
            primary: primary,
            selected: nil,
            page: nil,
            evidenceIssues: evidenceIssues
        )
    }

    private func boundedMap<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maximumConcurrent: Int,
        progress: (@MainActor @Sendable (Int) async -> Void)? = nil,
        operation: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Output] {
        guard inputs.isEmpty == false else {
            return []
        }
        let concurrency: Int = max(1, min(maximumConcurrent, inputs.count))
        return try await withThrowingTaskGroup(
            of: IndexedValue<Output>.self,
            returning: [Output].self
        ) { group in
            var nextIndex: Int = 0
            var completed: Int = 0
            var values: [Output?] = Array(repeating: nil, count: inputs.count)

            while nextIndex < concurrency {
                let index: Int = nextIndex
                let input: Input = inputs[index]
                group.addTask {
                    return IndexedValue(index: index, value: try await operation(input))
                }
                nextIndex += 1
            }

            while let indexedValue: IndexedValue<Output> = try await group.next() {
                values[indexedValue.index] = indexedValue.value
                completed += 1
                await progress?(completed)
                if nextIndex < inputs.count {
                    let index: Int = nextIndex
                    let input: Input = inputs[index]
                    group.addTask {
                        return IndexedValue(index: index, value: try await operation(input))
                    }
                    nextIndex += 1
                }
            }
            return values.compactMap { $0 }
        }
    }

    private func oneHopDecisions(
        observation: SourceListStructureObservation,
        inputURL: URL
    ) -> [VideoGenerationOneHopURLDecision] {
        return observation.groups.flatMap { group in
            group.members.compactMap { member -> VideoGenerationOneHopURLDecision? in
                guard let targetURL: URL = member.targetURL else {
                    return nil
                }
                let isPublic: Bool
                do {
                    try self.publicURLPolicy.validate(targetURL)
                    isPublic = true
                } catch {
                    isPublic = false
                }
                return VideoGenerationOneHopURLDecision(
                    ownerID: group.ownerID,
                    memberID: member.id,
                    url: targetURL,
                    isPublic: isPublic,
                    isSameSite: self.publicURLPolicy.isSameSite(targetURL, as: inputURL)
                )
            }
        }
    }

    private func detailPlan(
        inputObservation: SourceListStructureObservation,
        oneHopObservations: [SourceListLinkedObservation]
    ) -> (
        primary: [DetailWorkDescriptor],
        backups: [String: DetailWorkDescriptor],
        representedMembers: Set<String>,
        totalOwnerCount: Int
    ) {
        let allWork: [DetailWorkDescriptor] = self.allDetailWork(
            inputObservation: inputObservation,
            oneHopObservations: oneHopObservations
        )
        let groupedWork: [String: [DetailWorkDescriptor]] = Dictionary(grouping: allWork) { work in
            work.ownerKey
        }
        let ownerKeys: [String] = groupedWork.keys.sorted()
        var primary: [DetailWorkDescriptor] = []
        var backups: [String: DetailWorkDescriptor] = [:]
        var representedMembers: Set<String> = []

        for ownerKey: String in ownerKeys.prefix(self.samplingPolicy.maximumDetailPrimary) {
            let work: [DetailWorkDescriptor] = (groupedWork[ownerKey] ?? []).sorted { lhs, rhs in
                lhs.memberID < rhs.memberID
            }
            guard let first: DetailWorkDescriptor = work.first else {
                continue
            }
            primary.append(first)
            representedMembers.formUnion(work.map(\.memberID))
            if backups.count < self.samplingPolicy.maximumDetailBackups,
               let backup: DetailWorkDescriptor = work.dropFirst().last {
                backups[ownerKey] = backup
            }
        }
        return (
            primary: primary,
            backups: backups,
            representedMembers: representedMembers,
            totalOwnerCount: ownerKeys.count
        )
    }

    private func allDetailWork(
        inputObservation: SourceListStructureObservation,
        oneHopObservations: [SourceListLinkedObservation]
    ) -> [DetailWorkDescriptor] {
        var work: [DetailWorkDescriptor] = []
        let observations: [SourceListStructureObservation] = [inputObservation]
            + oneHopObservations.map(\.observation).filter { observation in
                switch observation.documentShape.kind {
                case .leafList, .directListCandidate, .mixedCandidate:
                    return true
                default:
                    return false
                }
            }
        for observation: SourceListStructureObservation in observations {
            for group: SourceListStructuralGroup in observation.groups
            where group.region == .content
                && group.canOwnPublicationItems
                && group.nestedGroupIDs.isEmpty {
                for member: SourceListStructuralMember in group.members {
                    guard let targetURL: URL = member.targetURL else {
                        continue
                    }
                    do {
                        try self.publicURLPolicy.validate(targetURL)
                    } catch {
                        continue
                    }
                    work.append(
                        DetailWorkDescriptor(
                            parentDocumentIdentity: observation.documentIdentity,
                            ownerID: group.ownerID,
                            memberID: member.id,
                            structuralGroupID: group.id,
                            url: targetURL
                        )
                    )
                }
            }
        }
        return Array(Set(work)).sorted { lhs, rhs in
            if lhs.ownerKey != rhs.ownerKey {
                return lhs.ownerKey < rhs.ownerKey
            }
            return lhs.memberID < rhs.memberID
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

    private func missingDetail(
        _ work: DetailWorkDescriptor,
        reason: SourceListMissingObservationReason
    ) -> SourceListMissingObservation {
        return SourceListMissingObservation(
            kind: .detail,
            parentDocumentIdentity: work.parentDocumentIdentity,
            parentOwnerID: work.ownerID,
            parentMemberID: work.memberID,
            reason: reason
        )
    }

    private func earlyEvidenceResult(
        issue: EvidenceIssue,
        inputURL: VideoGenerationInputURL
    ) -> VideoGenerationInputPreflight {
        return self.reducer.reduce(
            VideoGenerationInputReducerInput(
                inputURL: inputURL,
                entryShape: .ambiguous,
                familyCoverageState: .unresolved,
                acquisitionState: self.mergedAcquisitionState(.available, issue: issue),
                budgetExhausted: false,
                audit: VideoGenerationInputPreflightAudit(unresolvedFactCount: 1)
            )
        )
    }

    private func mergedAcquisitionState(
        _ current: VideoGenerationPreflightAcquisitionState,
        issue: EvidenceIssue
    ) -> VideoGenerationPreflightAcquisitionState {
        switch issue {
        case .antiBotChallenge:
            return .antiBotChallenge
        case .requiresUserSession:
            return current == .antiBotChallenge ? current : .requiresUserSession
        case .isolationUnavailable:
            return current == .available ? .isolationUnavailable : current
        }
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
