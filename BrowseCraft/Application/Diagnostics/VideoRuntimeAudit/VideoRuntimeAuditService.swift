// 中文注释：显式 runtime audit 只随 Debug 构建编译；Release/TestFlight 不含审计代码。
#if DEBUG
import Foundation
import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime

// 中文注释：显式 runtime audit 的执行结果对（BC-EVIDENCE-076.1）：session 与路线事实都来自
// 既有 playback loader 的单一 prepared session，不物化第二份执行状态。
enum VideoRuntimeAuditServiceError: Error, Equatable {
    case invalidCatalogRoot
    case credentialCatalogUnsupported
    case pageHasNoListEntry(String)
    case pageHasNoDetailEntry(String)
    case pageHasNoPlaybackEntry(String)
    case pageHasNoUsableDetailSample(String)
    case playbackSessionUnavailable(String)
    case declaredRuleBodyEncodingFailed(String)
}

// 中文注释：VideoRuntimeAuditService 是显式 runtime audit 的唯一驱动器（BC-EVIDENCE-076）。
// 它只经由现有 VideoSourceRuntime 的 loadList/loadDetail 与 playback loader 的单一 prepared
// session 驱动每个 catalog Page 的 list → detail → episode → playback，逐阶段产生脱敏 v2
// evidence，最终经 VideoRuntimeEvidenceExporter 严格校验后返回 JSON 字节。
// 无法建立唯一 owner binding 的路线如实输出 ambiguous/missing 并 failed，不伪造 unique。
struct VideoRuntimeAuditService {
    private static let maximumDetailAttempts: Int = 3
    /// 中文注释：BC-EVIDENCE-077.5——每个 group 首样本只做一次前台观察，等待上限 25 秒。
    static let webUIObservationTimeout: TimeInterval = 25

    private let runtimeFactory: VideoSourceRuntimeFactory
    private let mediaProbe: VideoRuntimeAuditMediaProbe
    private let materializer: CatalogSourceMaterializer
    /// 中文注释：BC-EVIDENCE-077.1——前台 WebUI 观察端口；nil 即 headless，行为与批次 3 相同。
    private let webUIObserver: (any VideoRuntimeAuditWebUIObserving)?

    init(
        runtimeFactory: VideoSourceRuntimeFactory,
        mediaProbe: VideoRuntimeAuditMediaProbe? = nil,
        materializer: CatalogSourceMaterializer = CatalogSourceMaterializer(),
        webUIObserver: (any VideoRuntimeAuditWebUIObserving)? = nil,
        browserRequestHeaderProvider: (any BrowserRequestHeaderProviding)? = nil
    ) {
        self.runtimeFactory = runtimeFactory
        // 中文注释：BC-EVIDENCE-079.4——探针默认带上与播放器同源的请求头提供者。
        self.mediaProbe = mediaProbe ?? VideoRuntimeAuditMediaProbe(
            browserRequestHeaderProvider: browserRequestHeaderProvider
        )
        self.materializer = materializer
        self.webUIObserver = webUIObserver
    }

    func run(catalogInput: VideoRuntimeAuditCatalogInput) async throws -> Data {
        let catalogSource: CatalogSource = try Self.catalogSource(from: catalogInput)
        // 中文注释：本里程碑不支持凭据注入；实际引用 userValue 的 catalog 整体拒绝，
        // 只声明 site.loginURL 的零凭据 catalog 按 BC-EVIDENCE-076.6 输出 login 形状结论。
        try Self.rejectCredentialCatalog(catalogInput)

        let now: Date = Date()
        let source: Source = try self.materializer.source(
            from: catalogSource,
            createdAt: now,
            updatedAt: now
        )
        let runtime: VideoSourceRuntime = try self.runtimeFactory.makeRuntime(source: source)
        let recorder: VideoRuntimeAuditRecorder = VideoRuntimeAuditRecorder(
            catalogInput: catalogInput
        )
        if let login: VideoRuntimeLoginEvidence = Self.loginShapeEvidence(
            catalogInput: catalogInput,
            baseURL: catalogSource.baseURL
        ) {
            await recorder.recordLogin(login)
        }
        var playbackContracts: [VideoRuntimePlaybackExportContract] = []

        for pageID: String in Self.orderedUniquePageIDs(runtime.resolvedRule) {
            let pageAudit: PageAuditResult = try await self.auditPage(
                pageID: pageID,
                runtime: runtime,
                catalogInput: catalogInput
            )
            for stage: VideoRuntimeStageEvidenceV2 in pageAudit.stages {
                try await recorder.record(stage)
            }
            // 中文注释：BC-EVIDENCE-079.3——页级失败局部化后该页没有 playback 阶段，也就没有合同。
            if let contract: VideoRuntimePlaybackExportContract = pageAudit.playbackContract {
                playbackContracts.append(contract)
            }
        }

        let evidence: VideoRuntimeEvidenceV2 = await recorder.snapshot()
        return try VideoRuntimeEvidenceExporter().export(
            evidence,
            catalogInput: catalogInput,
            playbackContracts: playbackContracts
        )
    }

    // MARK: - Page audit

    private struct PageAuditResult {
        let stages: [VideoRuntimeStageEvidenceV2]
        /// 中文注释：nil = 该页在 detail 阶段已局部失败，没有 playback 阶段（BC-EVIDENCE-079.3）。
        let playbackContract: VideoRuntimePlaybackExportContract?
    }

    private struct EpisodeGroup {
        let index: Int
        let ownerID: String
        let title: String?
        let firstEpisodeURL: URL
        let firstEpisodeHandoff: SourceVideoPlaybackHandoff?
    }

    private struct DetailChainProbe {
        let attempt: Int
        let fingerprint: VideoRuntimeEvidenceFingerprint
        let groups: [EpisodeGroup]
        let detailPassed: Bool
        let detailTitlePassed: Bool
        let detailCoverPassed: Bool
        let detailReadyStatus: VideoRuntimeEvidenceQualityStatus
        let episodeGroupTitleStatus: VideoRuntimeEvidenceQualityStatus
        let episodePassed: Bool
        let groupOneExecution: GroupPlaybackRecord?
        let detailLoadSucceeded: Bool
    }

    private struct GroupPlaybackRecord {
        let record: VideoRuntimePlaybackRouteEvidence
        let session: VideoPreparedPlaybackExecutionSession
        let passed: Bool
    }

    private func auditPage(
        pageID: String,
        runtime: VideoSourceRuntime,
        catalogInput: VideoRuntimeAuditCatalogInput
    ) async throws -> PageAuditResult {
        let resolvedRule: ResolvedVideoSiteRule = runtime.resolvedRule
        guard let listEntry: ResolvedVideoListEntry = resolvedRule.listEntries.first(
            where: { $0.pageID == pageID }
        ) else {
            throw VideoRuntimeAuditServiceError.pageHasNoListEntry(pageID)
        }
        guard let detailEntry: ResolvedVideoDetailEntry = resolvedRule.detailEntries.first(
            where: { $0.pageID == pageID }
        ) else {
            throw VideoRuntimeAuditServiceError.pageHasNoDetailEntry(pageID)
        }
        guard resolvedRule.playbackEntries.contains(where: { $0.pageID == pageID }) else {
            throw VideoRuntimeAuditServiceError.pageHasNoPlaybackEntry(pageID)
        }

        // 中文注释：list 阶段——page 1 一次真实加载；请求由 catalog owner 链派生（无任何 override），
        // 因此 requestMatchedCatalog 在加载成功时成立；失败时如实置 false。
        let listRule: VideoListRule = resolvedRule.listRule(for: listEntry)
        let listBranch: VideoRuntimeEvidenceBranch = Self.branch(
            for: listRule.effectiveSourceStrategy
        )
        let listRequest: RequestConfig? = listBranch == .api
            ? listEntry.effectiveListAPIRequest
            : listEntry.effectiveListRequest
        var listItems: [SourceContentItem] = []
        var listSucceeded: Bool = false
        do {
            let output: SourceListOutput = try await runtime.loadList(
                SourceListInput(
                    page: 1,
                    urlOverride: nil,
                    context: self.context(
                        sourceID: runtime.source.id,
                        pageID: pageID,
                        ruleID: listEntry.listRuleID,
                        operation: .list
                    )
                )
            )
            listItems = output.items
            listSucceeded = output.diagnostics.status == .succeeded && output.items.isEmpty == false
        } catch {
            listSucceeded = false
        }
        let listStage: VideoRuntimeStageEvidenceV2 = Self.dataStage(
            pageID: pageID,
            stage: .list,
            branch: listBranch,
            request: listRequest,
            requestMatchedCatalog: listSucceeded,
            parserContractPassed: listSucceeded,
            passed: listSucceeded,
            coverageComplete: listSucceeded,
            sampleCount: listItems.count
        )

        // 中文注释：detail 有界最佳链选择（BC-DETAIL-045：≤3，找到首个完整链即停）。
        let detailRule: VideoDetailRule = resolvedRule.detailRule(for: detailEntry)
        let detailBranch: VideoRuntimeEvidenceBranch = Self.branch(
            for: detailRule.effectiveSourceStrategy
        )
        let detailRequest: RequestConfig? = detailBranch == .api
            ? detailEntry.effectiveDetailAPIRequest
            : detailEntry.effectiveDetailRequest
        let detailReadyApplicable: Bool = detailBranch == .dom && detailRule.ready != nil
        // 中文注释：BC-EVIDENCE-076.7——评分布尔只复验 catalog 已声明的字段。
        let detailCoverDeclared: Bool = detailRule.fields?.cover != nil
        let episodeDeclared: Bool = resolvedRule.episodeRuleIfPresent(for: detailEntry) != nil

        let candidates: [SourceContentItem] = listItems.filter { $0.detailURL != nil }
        guard candidates.isEmpty == false else {
            // 中文注释：BC-EVIDENCE-079.3——没有可用 detail 样本只让本页 detail 阶段失败，
            // 不产出 episode/playback 阶段与合同，audit 继续其它页。
            let failedDetailStage: VideoRuntimeStageEvidenceV2 = Self.dataStage(
                pageID: pageID,
                stage: .detail,
                branch: detailBranch,
                request: detailRequest,
                requestMatchedCatalog: false,
                parserContractPassed: false,
                passed: false,
                coverageComplete: false,
                sampleCount: 0
            )
            return PageAuditResult(
                stages: [listStage, failedDetailStage],
                playbackContract: nil
            )
        }

        var probes: [DetailChainProbe] = []
        var selectedProbe: DetailChainProbe?
        for (offset, item) in candidates.prefix(Self.maximumDetailAttempts).enumerated() {
            let probe: DetailChainProbe = try await self.probeDetailChain(
                attempt: offset + 1,
                item: item,
                pageID: pageID,
                runtime: runtime,
                catalogInput: catalogInput,
                detailReadyApplicable: detailReadyApplicable,
                detailCoverDeclared: detailCoverDeclared,
                episodeDeclared: episodeDeclared
            )
            probes.append(probe)
            if Self.isCompleteChain(probe, detailReadyApplicable: detailReadyApplicable) {
                selectedProbe = probe
                break
            }
        }
        let selected: DetailChainProbe = selectedProbe
            ?? Self.bestIncompleteProbe(probes, detailReadyApplicable: detailReadyApplicable)

        // 中文注释：为 selected attempt 补齐剩余 expected group 的强制首样本（BC-EPISODE-004）。
        var groupRecords: [GroupPlaybackRecord] = []
        if let groupOne: GroupPlaybackRecord = selected.groupOneExecution {
            groupRecords.append(groupOne)
        }
        for group: EpisodeGroup in selected.groups.dropFirst() {
            let record: GroupPlaybackRecord = try await self.executeGroupPlayback(
                runtime: runtime,
                catalogInput: catalogInput,
                pageID: pageID,
                detailFingerprint: selected.fingerprint,
                group: group,
                sampleIndex: 1
            )
            groupRecords.append(record)
        }
        // 中文注释：BC-EVIDENCE-079.3——没有任何 group 的 playback session（detail 未给出 group）
        // 时，本页只到 detail/episode 阶段并如实失败，不产出 playback 阶段与合同。
        let contractSession: VideoPreparedPlaybackExecutionSession? = groupRecords.first?.session
        let playbackContract: VideoRuntimePlaybackExportContract? =
            try contractSession?.runtimePlaybackExportContract(detailBranch: detailBranch)

        let allGroupsPassed: Bool = selected.groups.isEmpty == false
            && groupRecords.count == selected.groups.count
            && groupRecords.allSatisfy(\.passed)

        // 中文注释：`BC-EVIDENCE-013`（09-03 修订）——attempt 级 `playbackPassed` 对每个 attempt
        // 只有一种语义：该链首 group 独立通过（本 service 每 group 只执行首样本，故即 group 1
        // 首样本；选样与提前停止本来就按此判定）。
        // 全部 expected group 的结论只在 playback stage 级（`passed`/`coverageComplete`）。此前
        // 把 selected attempt 事后改写成「全部 group 通过」，让同一字段两种语义、与 exporter /
        // 归约器的 earliest-best 复核冲突（kpkuang webkit 路线 09-03 实测拒绝导出）。
        let attempts: [VideoRuntimeDetailSampleAttemptEvidence] = probes.map { probe in
            VideoRuntimeDetailSampleAttemptEvidence(
                attempt: probe.attempt,
                detailSampleFingerprint: probe.fingerprint,
                detailPassed: probe.detailPassed,
                detailTitlePassed: probe.detailTitlePassed,
                detailReadyStatus: probe.detailReadyStatus,
                detailCoverPassed: probe.detailCoverPassed,
                episodeGroupTitleStatus: probe.episodeGroupTitleStatus,
                episodePassed: probe.episodePassed,
                playbackPassed: probe.groupOneExecution?.passed ?? false
            )
        }
        let sampleSelection: VideoRuntimeDetailSampleSelectionEvidence =
            VideoRuntimeDetailSampleSelectionEvidence(
                maximumAttempts: Self.maximumDetailAttempts,
                attemptedCount: attempts.count,
                selectedAttempt: selected.attempt,
                attempts: attempts
            )

        let detailChainPassed: Bool = selected.detailPassed
            && selected.detailTitlePassed
            && selected.detailCoverPassed
            && Self.qualityStatusPasses(
                selected.detailReadyStatus,
                applicable: detailReadyApplicable
            )
        let detailStage: VideoRuntimeStageEvidenceV2 = Self.dataStage(
            pageID: pageID,
            stage: .detail,
            branch: detailBranch,
            request: detailRequest,
            requestMatchedCatalog: selected.detailLoadSucceeded,
            parserContractPassed: selected.detailLoadSucceeded,
            passed: detailChainPassed,
            coverageComplete: detailChainPassed,
            sampleCount: attempts.count
        )

        var stages: [VideoRuntimeStageEvidenceV2] = [listStage, detailStage]
        if episodeDeclared {
            let episodeRule: VideoEpisodeRule = resolvedRule.episodeRule(for: detailEntry)
            let episodeBranch: VideoRuntimeEvidenceBranch = Self.branch(
                for: episodeRule.effectiveSourceStrategy
            )
            let episodeRequest: RequestConfig? = episodeBranch == .api
                ? detailEntry.effectiveEpisodeAPIRequest
                : detailEntry.effectiveEpisodeRequest
            let episodePassed: Bool = selected.episodePassed
                && Self.qualityStatusPasses(
                    selected.episodeGroupTitleStatus,
                    applicable: selected.groups.count > 1
                )
            stages.append(
                Self.dataStage(
                    pageID: pageID,
                    stage: .episode,
                    branch: episodeBranch,
                    request: episodeRequest,
                    requestMatchedCatalog: selected.detailLoadSucceeded,
                    parserContractPassed: selected.detailLoadSucceeded,
                    passed: episodePassed,
                    coverageComplete: episodePassed,
                    sampleCount: selected.groups.count
                )
            )
        }

        guard let contractSession: VideoPreparedPlaybackExecutionSession,
              let playbackContract: VideoRuntimePlaybackExportContract else {
            return PageAuditResult(stages: stages, playbackContract: nil)
        }
        let playbackNeedsWebView: Bool = contractSession.request?.needsWebView == true
        let routes: [VideoRuntimePlaybackRouteEvidence] = groupRecords.map(\.record)
        // 中文注释：BC-EVIDENCE-079.1——route 是实际到达的最终路线：任一 attempted 的 WebUI
        // attempt 即 webkit；resolvedNeedsWebView 保持 catalog owner 链的静态解析，两者可不同。
        let reachedWebUI: Bool = routes.contains { route in
            route.routeAttempts.contains { attempt in
                attempt.attempted && attempt.executionMode == .webUI
            }
        }
        stages.append(
            VideoRuntimeStageEvidenceV2(
                pageID: pageID,
                stage: .playback,
                branch: .playback,
                environment: .browseCraftApp,
                runtimeEquivalent: true,
                route: (playbackNeedsWebView || reachedWebUI) ? .webKit : .http,
                resolvedNeedsWebView: playbackNeedsWebView,
                requestMatchedCatalog: true,
                parserContractPassed: allGroupsPassed,
                passed: allGroupsPassed,
                coverageComplete: allGroupsPassed,
                sampleCount: routes.count,
                credentialStatus: Self.credentialStatus(for: contractSession.request),
                playback: VideoRuntimePlaybackEvidenceV2(
                    sampleSelection: sampleSelection,
                    expectedGroupOwnerIDs: selected.groups.map(\.ownerID),
                    routes: routes
                )
            )
        )
        return PageAuditResult(stages: stages, playbackContract: playbackContract)
    }

    // MARK: - Detail chain probing

    private func probeDetailChain(
        attempt: Int,
        item: SourceContentItem,
        pageID: String,
        runtime: VideoSourceRuntime,
        catalogInput: VideoRuntimeAuditCatalogInput,
        detailReadyApplicable: Bool,
        detailCoverDeclared: Bool,
        episodeDeclared: Bool
    ) async throws -> DetailChainProbe {
        guard let detailURL: URL = item.detailURL else {
            throw VideoRuntimeAuditServiceError.pageHasNoUsableDetailSample(pageID)
        }
        let fingerprint: VideoRuntimeEvidenceFingerprint =
            try VideoRuntimeEvidenceFingerprintFactory.detailSample(
                catalogSHA256: catalogInput.catalogSHA256,
                pageID: pageID,
                stableDetailURL: detailURL
            )

        var detailOutput: SourceDetailOutput?
        do {
            detailOutput = try await runtime.loadDetail(
                SourceDetailInput(
                    detailURL: detailURL,
                    context: self.context(
                        sourceID: runtime.source.id,
                        pageID: pageID,
                        ruleID: nil,
                        operation: .detail
                    ),
                    itemReference: item.itemReference
                )
            )
        } catch {
            detailOutput = nil
        }
        let detailLoadSucceeded: Bool = detailOutput?.diagnostics.status == .succeeded
        let metadata: SourceDetailMetadata? = detailOutput?.metadata
        let groups: [EpisodeGroup] = try Self.episodeGroups(
            from: detailOutput,
            pageID: pageID
        )

        // 中文注释：ready 由 detail loader 的分支门控承载——DOM 分支只有 readyMatched 才算
        // nonEmpty，因此「已声明 ready 且 DOM detail 加载成功」即 ready 通过的观察结果。
        let readyStatus: VideoRuntimeEvidenceQualityStatus
        if detailReadyApplicable {
            readyStatus = detailLoadSucceeded ? .passed : .failed
        } else {
            readyStatus = .notApplicable
        }
        let groupTitleStatus: VideoRuntimeEvidenceQualityStatus
        if groups.count > 1 {
            let allTitled: Bool = groups.allSatisfy { group in
                (group.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
            groupTitleStatus = allTitled ? .passed : .failed
        } else {
            groupTitleStatus = .notApplicable
        }
        let episodePassed: Bool
        if episodeDeclared {
            episodePassed = groups.isEmpty == false
        } else {
            episodePassed = detailOutput?.videoPlaybackAction != nil || groups.isEmpty == false
        }

        var groupOneExecution: GroupPlaybackRecord?
        if let firstGroup: EpisodeGroup = groups.first {
            groupOneExecution = try await self.executeGroupPlayback(
                runtime: runtime,
                catalogInput: catalogInput,
                pageID: pageID,
                detailFingerprint: fingerprint,
                group: firstGroup,
                sampleIndex: 1
            )
        }

        return DetailChainProbe(
            attempt: attempt,
            fingerprint: fingerprint,
            groups: groups,
            detailPassed: detailLoadSucceeded && metadata != nil,
            detailTitlePassed: Self.nonemptyText(metadata?.title),
            detailCoverPassed: detailCoverDeclared ? metadata?.coverURL != nil : true,
            detailReadyStatus: readyStatus,
            episodeGroupTitleStatus: groupTitleStatus,
            episodePassed: episodePassed,
            groupOneExecution: groupOneExecution,
            detailLoadSucceeded: detailLoadSucceeded
        )
    }

    private static func episodeGroups(
        from detailOutput: SourceDetailOutput?,
        pageID: String
    ) throws -> [EpisodeGroup] {
        guard let detailOutput: SourceDetailOutput = detailOutput else {
            return []
        }
        if detailOutput.chapters.isEmpty == false {
            var orderedSourceIndexes: [Int] = []
            var firstChapterBySourceIndex: [Int: SourceChapter] = [:]
            for chapter: SourceChapter in detailOutput.chapters {
                let sourceIndex: Int = chapter.videoPlaybackHandoff?.sourceIndex ?? 0
                if firstChapterBySourceIndex[sourceIndex] == nil {
                    firstChapterBySourceIndex[sourceIndex] = chapter
                    orderedSourceIndexes.append(sourceIndex)
                }
            }
            return try orderedSourceIndexes.enumerated().map { offset, sourceIndex in
                let chapter: SourceChapter = firstChapterBySourceIndex[sourceIndex]!
                return EpisodeGroup(
                    index: offset + 1,
                    ownerID: try VideoRuntimeEvidenceFingerprintFactory.groupOwnerID(
                        pageID: pageID,
                        groupIndex: offset + 1
                    ),
                    title: chapter.videoPlaybackHandoff?.sourceName,
                    firstEpisodeURL: chapter.url,
                    firstEpisodeHandoff: chapter.videoPlaybackHandoff
                )
            }
        }
        if let action: SourceVideoDetailPlaybackAction = detailOutput.videoPlaybackAction {
            // 中文注释：document-self 直达播放使用该 Page 的唯一 synthetic group owner（BC-EVIDENCE-014）。
            return [
                EpisodeGroup(
                    index: 1,
                    ownerID: try VideoRuntimeEvidenceFingerprintFactory.groupOwnerID(
                        pageID: pageID,
                        groupIndex: 1
                    ),
                    title: action.sourceName,
                    firstEpisodeURL: action.playPageURL,
                    firstEpisodeHandoff: action.handoff
                )
            ]
        }
        return []
    }

    // MARK: - Group playback execution

    private func executeGroupPlayback(
        runtime: VideoSourceRuntime,
        catalogInput: VideoRuntimeAuditCatalogInput,
        pageID: String,
        detailFingerprint: VideoRuntimeEvidenceFingerprint,
        group: EpisodeGroup,
        sampleIndex: Int
    ) async throws -> GroupPlaybackRecord {
        let execution: VideoAuditPlaybackExecution = try await runtime.auditPlaybackWithRouteFacts(
            SourceVideoPlaybackInput(
                playPageURL: group.firstEpisodeURL,
                context: self.context(
                    sourceID: runtime.source.id,
                    pageID: pageID,
                    ruleID: nil,
                    operation: .playback
                ),
                handoff: group.firstEpisodeHandoff
            )
        )
        let session: VideoPreparedPlaybackExecutionSession = execution.session
        let playbackReference: SourceVideoPlaybackReference? = execution.result?.output.reference
        let playbackRequestConfig: SourcePlaybackRequestConfig? =
            playbackReference?.playbackRequestConfig

        var attempts: [VideoRuntimeRouteAttemptEvidence] = []
        var priorRoutePassed: Bool = false
        var priorSelectionFailed: Bool = false
        var selectedRouteSlot: VideoRuntimeEvidenceRouteSlot?
        for declared: VideoPreparedPlaybackDeclaredRoute in session.declaredRoutes {
            let routeFingerprint: VideoRuntimeEvidenceFingerprint = try self.routeFingerprint(
                catalogInput: catalogInput,
                pageID: pageID,
                detailFingerprint: detailFingerprint,
                groupOwnerID: group.ownerID,
                declared: declared,
                session: session
            )
            let attempt: VideoRuntimeRouteAttemptEvidence = try await self.routeAttempt(
                declared: declared,
                fact: execution.result?.routeFacts.first { $0.routeSlot == declared.routeSlot },
                routeFingerprint: routeFingerprint,
                playbackReference: playbackReference,
                playbackRequestConfig: playbackRequestConfig,
                playbackRule: session.playbackRule,
                priorRoutePassed: priorRoutePassed,
                priorSelectionFailed: priorSelectionFailed,
                executionAvailable: execution.result != nil
            )
            if attempt.passed {
                priorRoutePassed = true
                selectedRouteSlot = attempt.routeSlot
            } else if attempt.attempted {
                // 中文注释：loader 已选中却未通过最终媒体观察时，后续槽位仍逐个评估并如实 failed，
                // 不得输出与「prior route passed」语义冲突的 skip（BC-EVIDENCE-019）。
                priorSelectionFailed = true
            }
            attempts.append(attempt)
        }

        return GroupPlaybackRecord(
            record: VideoRuntimePlaybackRouteEvidence(
                detailSampleFingerprint: detailFingerprint,
                groupOwnerID: group.ownerID,
                groupIndex: group.index,
                sampleIndex: sampleIndex,
                selectedRouteSlot: selectedRouteSlot,
                routeAttempts: attempts
            ),
            session: session,
            passed: selectedRouteSlot != nil
        )
    }

    private func routeAttempt(
        declared: VideoPreparedPlaybackDeclaredRoute,
        fact: VideoPreparedPlaybackRouteFact?,
        routeFingerprint: VideoRuntimeEvidenceFingerprint,
        playbackReference: SourceVideoPlaybackReference?,
        playbackRequestConfig: SourcePlaybackRequestConfig?,
        playbackRule: VideoPlaybackRule,
        priorRoutePassed: Bool,
        priorSelectionFailed: Bool,
        executionAvailable: Bool
    ) async throws -> VideoRuntimeRouteAttemptEvidence {
        if priorRoutePassed {
            return VideoRuntimeRouteAttemptEvidence(
                routeSlot: declared.routeSlot,
                executionMode: declared.executionMode,
                attempted: false,
                passed: false,
                routeFingerprint: routeFingerprint,
                skipReason: .priorRouteSelected
            )
        }
        guard executionAvailable else {
            return self.failedAttempt(
                declared: declared,
                routeFingerprint: routeFingerprint,
                reason: "playback-execution-failed"
            )
        }
        guard let fact: VideoPreparedPlaybackRouteFact = fact else {
            return self.failedAttempt(
                declared: declared,
                routeFingerprint: routeFingerprint,
                reason: "route-fact-unavailable"
            )
        }

        switch fact.disposition {
        case .skipped:
            // 中文注释：loader 侧 skip 只发生在前序槽位已被选中；若前序选中却未通过观察，
            // 该槽位改判为「已评估、无观察点」的 failed（见 priorSelectionFailed 分支）。
            if priorSelectionFailed {
                return self.failedAttempt(
                    declared: declared,
                    routeFingerprint: routeFingerprint,
                    reason: "final-media-observation-unavailable"
                )
            }
            return self.failedAttempt(
                declared: declared,
                routeFingerprint: routeFingerprint,
                reason: "route-not-reached"
            )
        case .rejectedBeforePlayer:
            // 中文注释：BC-EVIDENCE-079.2——loader 判为明确加密的直连媒体，仍对候选做 076.4 同一有界
            // 读取，输出 hls/encrypted 与完整媒体事实（passed=false），让归约得出 encrypted-media。
            if (fact.reason == .encryptedHLS || fact.reason == .knownEncryptedMedia),
               declared.executionMode != .webUI,
               fact.candidateMediaURL != nil,
               fact.candidateMediaKind != .unknown {
                return await self.observedAttempt(
                    declared: declared,
                    fact: fact,
                    routeFingerprint: routeFingerprint,
                    playbackRequestConfig: playbackRequestConfig
                )
            }
            return self.failedAttempt(
                declared: declared,
                routeFingerprint: routeFingerprint,
                reason: Self.rejectionCode(for: fact.reason)
            )
        case .selectedForPlayer:
            if declared.executionMode == .webUI {
                return await self.observedWebUIAttempt(
                    declared: declared,
                    routeFingerprint: routeFingerprint,
                    playbackReference: playbackReference,
                    playbackRequestConfig: playbackRequestConfig,
                    playbackRule: playbackRule
                )
            }
            return await self.observedAttempt(
                declared: declared,
                fact: fact,
                routeFingerprint: routeFingerprint,
                playbackRequestConfig: playbackRequestConfig
            )
        }
    }

    private func observedAttempt(
        declared: VideoPreparedPlaybackDeclaredRoute,
        fact: VideoPreparedPlaybackRouteFact,
        routeFingerprint: VideoRuntimeEvidenceFingerprint,
        playbackRequestConfig: SourcePlaybackRequestConfig?
    ) async -> VideoRuntimeRouteAttemptEvidence {
        guard let mediaURL: URL = fact.candidateMediaURL,
              fact.candidateMediaKind != .unknown else {
            return self.failedAttempt(
                declared: declared,
                routeFingerprint: routeFingerprint,
                reason: "final-media-candidate-unavailable"
            )
        }
        let probeResult: Result<VideoRuntimeAuditMediaObservation, VideoRuntimeAuditMediaProbeFailure> =
            await self.mediaProbe.observe(
                mediaURL: mediaURL,
                kind: fact.candidateMediaKind,
                playbackRequestConfig: playbackRequestConfig
            )
        return self.observedMediaAttempt(
            declared: declared,
            routeFingerprint: routeFingerprint,
            probeResult: probeResult,
            playbackSessionID: UUID(),
            playerStarted: nil
        )
    }

    /// 中文注释：BC-EVIDENCE-077——WebUI 路线：前台观察 → 021 归约 → unique 时对 currentSrc
    /// 做 076.4 同一有界验收。无观察端口（headless）时与批次 3 逐字节相同。
    /// 中文注释：`BC-EVIDENCE-078.1`——激活对象只来自 catalog 声明：iframe.url 的 css 选择器，
    /// 无 iframe 规则时取 media.url；非 css 或为空则不激活。
    static func activationSelector(playbackRule: VideoPlaybackRule) -> String? {
        let extractRule: ExtractRule? = playbackRule.iframe?.url
            ?? playbackRule.media?.url
            ?? playbackRule.effectiveMediaCandidates.first?.url
        return VideoRuntimeAuditActivationSelector.cssSelector(
            selector: extractRule?.selector,
            selectorKind: extractRule?.selectorKind?.rawValue
        )
    }

    private func observedWebUIAttempt(
        declared: VideoPreparedPlaybackDeclaredRoute,
        routeFingerprint: VideoRuntimeEvidenceFingerprint,
        playbackReference: SourceVideoPlaybackReference?,
        playbackRequestConfig: SourcePlaybackRequestConfig?,
        playbackRule: VideoPlaybackRule
    ) async -> VideoRuntimeRouteAttemptEvidence {
        guard let observer: any VideoRuntimeAuditWebUIObserving = self.webUIObserver,
              let reference: SourceVideoPlaybackReference = playbackReference else {
            return self.failedAttempt(
                declared: declared,
                routeFingerprint: routeFingerprint,
                reason: "player-session-binding-unavailable",
                playerStarted: false
            )
        }
        let playbackSessionID: UUID = UUID()
        let observation: VideoRuntimeAuditWebUIObservation = await observer.observe(
            reference: reference,
            requestConfig: playbackRequestConfig,
            sessionToken: playbackSessionID.uuidString.lowercased(),
            timeout: Self.webUIObservationTimeout,
            activationSelector: Self.activationSelector(playbackRule: playbackRule)
        )
        switch observation.bindingStatus {
        case .missing:
            // 中文注释：`BC-EVIDENCE-078.5`——原因码的唯一定义点在 observation 上。
            return self.failedAttempt(
                declared: declared,
                routeFingerprint: routeFingerprint,
                reason: observation.missingBindingRejectionReason,
                playerStarted: observation.playerStarted
            )
        case .ambiguous:
            return self.failedAttempt(
                declared: declared,
                routeFingerprint: routeFingerprint,
                reason: "final-media-binding-ambiguous",
                playerStarted: observation.playerStarted,
                bindingStatus: .ambiguous
            )
        case .unique:
            guard let mediaURL: URL = observation.mediaURL else {
                return self.failedAttempt(
                    declared: declared,
                    routeFingerprint: routeFingerprint,
                    reason: "final-media-observation-unavailable",
                    playerStarted: observation.playerStarted
                )
            }
            let probeResult: Result<VideoRuntimeAuditMediaObservation, VideoRuntimeAuditMediaProbeFailure> =
                await self.mediaProbe.observeSniffingKind(
                    mediaURL: mediaURL,
                    playbackRequestConfig: playbackRequestConfig
                )
            return self.observedMediaAttempt(
                declared: declared,
                routeFingerprint: routeFingerprint,
                probeResult: probeResult,
                playbackSessionID: playbackSessionID,
                playerStarted: true
            )
        }
    }

    private func observedMediaAttempt(
        declared: VideoPreparedPlaybackDeclaredRoute,
        routeFingerprint: VideoRuntimeEvidenceFingerprint,
        probeResult: Result<VideoRuntimeAuditMediaObservation, VideoRuntimeAuditMediaProbeFailure>,
        playbackSessionID: UUID,
        playerStarted: Bool?
    ) -> VideoRuntimeRouteAttemptEvidence {
        switch probeResult {
        case .failure(let failure):
            return self.failedAttempt(
                declared: declared,
                routeFingerprint: routeFingerprint,
                reason: failure.rejectionReasonCode,
                playerStarted: playerStarted
            )
        case .success(let observation):
            let ownerFingerprint: VideoRuntimeEvidenceFingerprint? =
                try? VideoRuntimeEvidenceFingerprintFactory.owner(
                    routeFingerprint: routeFingerprint,
                    playbackSessionID: playbackSessionID
                )
            let mediaFingerprint: VideoRuntimeEvidenceFingerprint? =
                try? VideoRuntimeEvidenceFingerprintFactory.media(
                    kind: observation.mediaKind,
                    resourceURL: observation.finalURL
                )
            guard let ownerFingerprint: VideoRuntimeEvidenceFingerprint = ownerFingerprint,
                  let mediaFingerprint: VideoRuntimeEvidenceFingerprint = mediaFingerprint else {
                return self.failedAttempt(
                    declared: declared,
                    routeFingerprint: routeFingerprint,
                    reason: "media-identity-unavailable",
                    playerStarted: playerStarted
                )
            }
            let encrypted: Bool = observation.encryptionStatus == .encrypted
            return VideoRuntimeRouteAttemptEvidence(
                routeSlot: declared.routeSlot,
                executionMode: declared.executionMode,
                attempted: true,
                passed: encrypted == false,
                routeFingerprint: routeFingerprint,
                resolvedMediaKind: observation.mediaKind,
                resolvedMediaFingerprint: mediaFingerprint,
                resolvedMediaBinding: VideoRuntimeMediaBindingEvidence(
                    status: .unique,
                    method: Self.bindingMethod(for: declared.executionMode),
                    ownerFingerprint: ownerFingerprint
                ),
                encryptionStatus: observation.encryptionStatus,
                mediaResponsePassed: true,
                bytesRead: observation.bytesRead,
                contentType: observation.contentType,
                manifestPassed: observation.manifestPassed,
                firstMediaReferencePassed: observation.firstMediaReferencePassed,
                playerStarted: declared.executionMode == .webUI ? (playerStarted ?? true) : nil,
                rejectionReason: encrypted
                    ? Self.rejectionReason("encrypted-hls-manifest")
                    : nil
            )
        }
    }

    private func failedAttempt(
        declared: VideoPreparedPlaybackDeclaredRoute,
        routeFingerprint: VideoRuntimeEvidenceFingerprint,
        reason: String,
        playerStarted: Bool? = nil,
        bindingStatus: VideoRuntimeEvidenceMediaBindingStatus = .missing
    ) -> VideoRuntimeRouteAttemptEvidence {
        let resolvedPlayerStarted: Bool? = declared.executionMode == .webUI
            ? (playerStarted ?? false)
            : nil
        return VideoRuntimeRouteAttemptEvidence(
            routeSlot: declared.routeSlot,
            executionMode: declared.executionMode,
            attempted: true,
            passed: false,
            routeFingerprint: routeFingerprint,
            resolvedMediaKind: .unknown,
            resolvedMediaBinding: VideoRuntimeMediaBindingEvidence(
                status: bindingStatus,
                method: Self.bindingMethod(for: declared.executionMode)
            ),
            encryptionStatus: .unknown,
            playerStarted: resolvedPlayerStarted,
            rejectionReason: Self.rejectionReason(reason)
        )
    }

    private func routeFingerprint(
        catalogInput: VideoRuntimeAuditCatalogInput,
        pageID: String,
        detailFingerprint: VideoRuntimeEvidenceFingerprint,
        groupOwnerID: String,
        declared: VideoPreparedPlaybackDeclaredRoute,
        session: VideoPreparedPlaybackExecutionSession
    ) throws -> VideoRuntimeEvidenceFingerprint {
        let ruleBody: Data = try Self.declaredRuleBody(
            declared: declared,
            playbackRule: session.playbackRule,
            pageID: pageID
        )
        return try VideoRuntimeEvidenceFingerprintFactory.route(
            catalogSHA256: catalogInput.catalogSHA256,
            pageID: pageID,
            detailSampleFingerprint: detailFingerprint,
            groupOwnerID: groupOwnerID,
            routeSlot: declared.routeSlot,
            declaredRuleBody: ruleBody
        )
    }

    private static func declaredRuleBody(
        declared: VideoPreparedPlaybackDeclaredRoute,
        playbackRule: VideoPlaybackRule,
        pageID: String
    ) throws -> Data {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            switch declared.routeSlot {
            case .media:
                if let media: VideoDirectMediaRule = playbackRule.media {
                    return try encoder.encode(media)
                }
                let candidates: [VideoDirectMediaRule] = playbackRule.effectiveMediaCandidates
                if candidates.isEmpty == false {
                    return try encoder.encode(candidates)
                }
                throw VideoRuntimeAuditServiceError.declaredRuleBodyEncodingFailed(pageID)
            case .iframe:
                guard let iframe: VideoIframePlaybackRule = playbackRule.iframe else {
                    throw VideoRuntimeAuditServiceError.declaredRuleBodyEncodingFailed(pageID)
                }
                return try encoder.encode(iframe)
            case .fallback:
                return Data("fallback:webUI".utf8)
            }
        } catch is EncodingError {
            throw VideoRuntimeAuditServiceError.declaredRuleBodyEncodingFailed(pageID)
        }
    }

    // MARK: - Selection helpers

    private static func isCompleteChain(
        _ probe: DetailChainProbe,
        detailReadyApplicable: Bool
    ) -> Bool {
        return probe.detailPassed
            && probe.detailTitlePassed
            && probe.detailCoverPassed
            && probe.episodePassed
            && (probe.groupOneExecution?.passed ?? false)
            && Self.qualityStatusPasses(probe.detailReadyStatus, applicable: detailReadyApplicable)
            && Self.qualityStatusPasses(
                probe.episodeGroupTitleStatus,
                applicable: probe.groups.count > 1
            )
    }

    private static func bestIncompleteProbe(
        _ probes: [DetailChainProbe],
        detailReadyApplicable: Bool
    ) -> DetailChainProbe {
        precondition(probes.isEmpty == false)
        var best: DetailChainProbe = probes[0]
        var bestScore: Int = Self.score(probes[0], detailReadyApplicable: detailReadyApplicable)
        for probe: DetailChainProbe in probes.dropFirst() {
            let score: Int = Self.score(probe, detailReadyApplicable: detailReadyApplicable)
            if score > bestScore {
                best = probe
                bestScore = score
            }
        }
        return best
    }

    private static func score(
        _ probe: DetailChainProbe,
        detailReadyApplicable: Bool
    ) -> Int {
        var score: Int = [
            probe.detailPassed,
            probe.detailTitlePassed,
            probe.detailCoverPassed,
            probe.episodePassed,
            probe.groupOneExecution?.passed ?? false
        ].filter { $0 }.count
        score += Self.qualityStatusPasses(
            probe.detailReadyStatus,
            applicable: detailReadyApplicable
        ) ? 1 : 0
        score += Self.qualityStatusPasses(
            probe.episodeGroupTitleStatus,
            applicable: probe.groups.count > 1
        ) ? 1 : 0
        return score
    }

    private static func qualityStatusPasses(
        _ status: VideoRuntimeEvidenceQualityStatus,
        applicable: Bool
    ) -> Bool {
        if applicable {
            return status == .passed
        }
        return status == .passed || status == .notApplicable
    }

    // MARK: - Shared helpers

    private func context(
        sourceID: String,
        pageID: String,
        ruleID: String?,
        operation: SourceRuntimeOperation
    ) -> SourceRuntimeContext {
        return SourceRuntimeContext(
            sourceID: sourceID,
            pageID: pageID,
            tabID: nil,
            ruleID: ruleID,
            requestOverride: nil,
            debugMode: false,
            operation: operation
        )
    }

    private static func dataStage(
        pageID: String,
        stage: VideoRuntimeEvidenceStage,
        branch: VideoRuntimeEvidenceBranch,
        request: RequestConfig?,
        requestMatchedCatalog: Bool,
        parserContractPassed: Bool,
        passed: Bool,
        coverageComplete: Bool,
        sampleCount: Int
    ) -> VideoRuntimeStageEvidenceV2 {
        let needsWebView: Bool = request?.needsWebView == true
        return VideoRuntimeStageEvidenceV2(
            pageID: pageID,
            stage: stage,
            branch: branch,
            environment: .browseCraftApp,
            runtimeEquivalent: true,
            route: needsWebView ? .webKit : .http,
            resolvedNeedsWebView: needsWebView,
            requestMatchedCatalog: requestMatchedCatalog,
            parserContractPassed: parserContractPassed,
            passed: passed,
            coverageComplete: coverageComplete,
            sampleCount: sampleCount,
            credentialStatus: Self.credentialStatus(for: request)
        )
    }

    private static func branch(
        for strategy: VideoRuleDataSourceStrategy
    ) -> VideoRuntimeEvidenceBranch {
        switch strategy {
        case .apiOnly:
            return .api
        case .domOnly, .domThenAPI, .apiThenDOM:
            // 中文注释：混合策略的实际分支未在输出中暴露；当前发布合同产出单一策略规则，
            // 混合场景按 DOM 主分支记录并由生成侧归约器复核。
            return .dom
        }
    }

    private static func credentialStatus(
        for request: RequestConfig?
    ) -> VideoRuntimeEvidenceCredentialStatus {
        // 中文注释：本里程碑只支持无凭据 catalog；请求声明 cookiePolicy 时如实报 not-run，
        // 不伪造 validated。
        return request?.cookiePolicy == nil ? .notRequired : .notRun
    }

    private static func bindingMethod(
        for mode: VideoRuntimeEvidenceExecutionMode
    ) -> VideoRuntimeEvidenceMediaBindingMethod {
        switch mode {
        case .directMedia:
            return .nativeRequest
        case .iframeResolve:
            return .declaredIframeNavigation
        case .webUI:
            return .webUIPlayerSession
        }
    }

    private static func rejectionCode(
        for reason: VideoPreparedPlaybackRouteReason?
    ) -> String {
        switch reason {
        case .noCandidate:
            return "no-route-candidate"
        case .allCandidatesFilteredAsNoise:
            return "all-candidates-filtered-as-noise"
        case .encryptedHLS:
            return "encrypted-hls-manifest"
        case .knownEncryptedMedia:
            return "known-encrypted-media"
        case .finalMediaObservationUnavailable:
            return "final-media-observation-unavailable"
        case .iframeDepthExceeded:
            return "iframe-depth-exceeded"
        case .iframeLoopDetected:
            return "iframe-loop-detected"
        case .ambiguousIframeCandidates:
            return "ambiguous-iframe-candidates"
        case .priorRouteSelected:
            return "route-not-reached"
        case nil:
            return "route-rejected"
        }
    }

    private static func rejectionReason(_ code: String) -> VideoRuntimeEvidenceRejectionReason {
        return VideoRuntimeEvidenceRejectionReason(rawValue: code)
            ?? VideoRuntimeEvidenceRejectionReason(rawValue: "audit-internal-error")!
    }

    private static func orderedUniquePageIDs(_ resolvedRule: ResolvedVideoSiteRule) -> [String] {
        var seen: Set<String> = []
        var pageIDs: [String] = []
        for entry: ResolvedVideoListEntry in resolvedRule.listEntries {
            if seen.insert(entry.pageID).inserted {
                pageIDs.append(entry.pageID)
            }
        }
        return pageIDs
    }

    private static func catalogSource(
        from catalogInput: VideoRuntimeAuditCatalogInput
    ) throws -> CatalogSource {
        guard let root: [String: Any] = try? JSONSerialization.jsonObject(
            with: catalogInput.rawCatalogData
        ) as? [String: Any],
        let id: String = root["id"] as? String,
        let name: String = root["name"] as? String,
        let baseURL: String = root["baseURL"] as? String,
        let ruleJSONObject: [String: Any] = root["ruleJSON"] as? [String: Any],
        let ruleJSONData: Data = try? JSONSerialization.data(
            withJSONObject: ruleJSONObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else {
            throw VideoRuntimeAuditServiceError.invalidCatalogRoot
        }
        return CatalogSource(
            id: id,
            name: name,
            baseURL: baseURL,
            kind: .video,
            ruleJSON: String(decoding: ruleJSONData, as: UTF8.self)
        )
    }

    private static func rejectCredentialCatalog(
        _ catalogInput: VideoRuntimeAuditCatalogInput
    ) throws {
        guard let root: Any = try? JSONSerialization.jsonObject(
            with: catalogInput.rawCatalogData
        ) else {
            throw VideoRuntimeAuditServiceError.invalidCatalogRoot
        }
        if Self.containsCredentialMarker(root) {
            throw VideoRuntimeAuditServiceError.credentialCatalogUnsupported
        }
    }

    private static func containsCredentialMarker(_ value: Any) -> Bool {
        return Self.containsKey(value, key: "userValue")
    }

    private static func containsKey(_ value: Any, key: String) -> Bool {
        if let object: [String: Any] = value as? [String: Any] {
            for (childKey, child) in object {
                if childKey == key {
                    return true
                }
                if Self.containsKey(child, key: key) {
                    return true
                }
            }
            return false
        }
        if let array: [Any] = value as? [Any] {
            return array.contains { Self.containsKey($0, key: key) }
        }
        return false
    }

    // 中文注释：BC-EVIDENCE-076.6——零凭据 catalog 的 login 形状结论。cookie 发送链与
    // credentialStore 引用的验证对象为空集时为真；存在验证对象而本里程碑未验证时如实为 false。
    private static func loginShapeEvidence(
        catalogInput: VideoRuntimeAuditCatalogInput,
        baseURL: String
    ) -> VideoRuntimeLoginEvidence? {
        guard let root: Any = try? JSONSerialization.jsonObject(
            with: catalogInput.rawCatalogData
        ), let rootObject: [String: Any] = root as? [String: Any],
        let ruleJSON: [String: Any] = rootObject["ruleJSON"] as? [String: Any] else {
            return nil
        }
        guard let site: [String: Any] = ruleJSON["site"] as? [String: Any],
              let loginURLString: String = site["loginURL"] as? String else {
            return nil
        }
        let loginURLMatched: Bool = Self.loginURLMatchesCatalog(
            loginURLString,
            baseURL: baseURL
        )
        let hasCookiePolicy: Bool = Self.containsKey(ruleJSON, key: "cookiePolicy")
        let hasCredentialStoreReference: Bool = String(
            decoding: catalogInput.rawCatalogData,
            as: UTF8.self
        ).contains("{credentialStore.")
        return VideoRuntimeLoginEvidence(
            required: true,
            loginURLMatchedCatalog: loginURLMatched,
            cookieDomainValidated: hasCookiePolicy == false,
            credentialReferencesValidated: hasCredentialStoreReference == false,
            valuesRedacted: true
        )
    }

    private static func loginURLMatchesCatalog(
        _ loginURLString: String,
        baseURL: String
    ) -> Bool {
        guard let loginURL: URL = URL(string: loginURLString),
              let loginScheme: String = loginURL.scheme?.lowercased(),
              loginScheme == "http" || loginScheme == "https",
              let loginHost: String = loginURL.host?.lowercased(),
              let baseHost: String = URL(string: baseURL)?.host?.lowercased() else {
            return false
        }
        return loginHost == baseHost || loginHost.hasSuffix("." + baseHost)
    }

    private static func nonemptyText(_ value: String?) -> Bool {
        guard let value: String = value else {
            return false
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
#endif
