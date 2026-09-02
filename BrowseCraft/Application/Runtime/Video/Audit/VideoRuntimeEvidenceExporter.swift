import Foundation
import BrowseCraftCore

struct VideoRuntimeDeclaredRouteContract: Hashable, Sendable {
    let routeSlot: VideoRuntimeEvidenceRouteSlot
    let executionMode: VideoRuntimeEvidenceExecutionMode
}

// 中文注释：该投影由后续单一 prepared playback session 从既有 ResolvedVideoSiteRule 产生，不解析第二棵规则树。
struct VideoRuntimePlaybackExportContract: Hashable, Sendable {
    let pageID: String
    let detailReadyApplicable: Bool
    let declaredMediaKind: VideoRuntimeEvidenceMediaKind?
    let declaredRoutes: [VideoRuntimeDeclaredRouteContract]
}

enum VideoRuntimePlaybackExportContractProjectionError: Error, Equatable {
    case invalidDetailBranch
    case unsupportedMediaCandidates(count: Int)
}

extension VideoPreparedPlaybackExecutionSession {
    // 中文注释：Detail branch 必须来自同一 audit chain 的实际执行结果，不从 sourceStrategy 猜测。
    func runtimePlaybackExportContract(
        detailBranch: VideoRuntimeEvidenceBranch
    ) throws -> VideoRuntimePlaybackExportContract {
        guard detailBranch == .dom || detailBranch == .api else {
            throw VideoRuntimePlaybackExportContractProjectionError.invalidDetailBranch
        }
        if let mediaCandidates = self.playbackRule.mediaCandidates {
            // 中文注释：当前发布规范只允许单一 media；多候选不能折叠成一条安全证据。
            throw VideoRuntimePlaybackExportContractProjectionError.unsupportedMediaCandidates(
                count: mediaCandidates.count
            )
        }

        let declaredMediaKind: VideoRuntimeEvidenceMediaKind?
        if let media = self.playbackRule.media {
            declaredMediaKind = Self.runtimeMediaKind(media.kind)
        } else {
            declaredMediaKind = nil
        }

        return VideoRuntimePlaybackExportContract(
            pageID: self.entry.pageID,
            detailReadyApplicable: detailBranch == .dom && self.detailReadyDeclared,
            declaredMediaKind: declaredMediaKind,
            declaredRoutes: self.declaredRoutes.map { route in
                VideoRuntimeDeclaredRouteContract(
                    routeSlot: route.routeSlot,
                    executionMode: route.executionMode
                )
            }
        )
    }

    private static func runtimeMediaKind(
        _ kind: VideoDirectMediaKind
    ) -> VideoRuntimeEvidenceMediaKind {
        switch kind {
        case .hls:
            return .hls
        case .mp4:
            return .mp4
        }
    }
}

enum VideoRuntimeEvidenceExportError: Error, Equatable {
    case catalogHashMismatch
    case invalid(path: String, reason: String)
    case encodingFailed
}

struct VideoRuntimeEvidenceExporter {
    func export(
        _ evidence: VideoRuntimeEvidenceV2,
        catalogInput: VideoRuntimeAuditCatalogInput,
        playbackContracts: [VideoRuntimePlaybackExportContract]
    ) throws -> Data {
        guard evidence.catalogSHA256 == catalogInput.catalogSHA256 else {
            throw VideoRuntimeEvidenceExportError.catalogHashMismatch
        }
        try VideoRuntimeEvidenceV2Validator(
            playbackContracts: playbackContracts
        ).validate(evidence)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(evidence)
        } catch {
            throw VideoRuntimeEvidenceExportError.encodingFailed
        }
    }
}

private struct VideoRuntimeEvidenceV2Validator {
    private static let maximumStageRecords: Int = 512
    private static let maximumDetailAttempts: Int = 3
    private static let maximumGroupOwners: Int = 100
    private static let maximumSamplesPerGroup: Int = 3

    private let playbackContracts: [String: VideoRuntimePlaybackExportContract]

    init(playbackContracts: [VideoRuntimePlaybackExportContract]) throws {
        var contracts: [String: VideoRuntimePlaybackExportContract] = [:]
        for (index, contract) in playbackContracts.enumerated() {
            let path: String = "$.playbackContracts[\(index)]"
            let pageID: String = try Self.nonempty(contract.pageID, path: "\(path).pageID")
            guard contracts[pageID] == nil else {
                throw Self.invalid(path, "duplicate pageID")
            }
            try Self.validateDeclaredRoutes(contract, path: path)
            contracts[pageID] = contract
        }
        self.playbackContracts = contracts
    }

    func validate(_ evidence: VideoRuntimeEvidenceV2) throws {
        guard evidence.schemaVersion == 2 else {
            throw Self.invalid("$.schemaVersion", "must equal 2")
        }
        guard evidence.stages.isEmpty == false,
              evidence.stages.count <= Self.maximumStageRecords else {
            throw Self.invalid("$.stages", "must contain 1...512 records")
        }
        guard Set(evidence.blockedCapabilities).count == evidence.blockedCapabilities.count else {
            throw Self.invalid("$.blockedCapabilities", "contains duplicates")
        }

        var stageKeys: Set<StageKey> = []
        var playbackPageIDs: Set<String> = []
        for (index, stage) in evidence.stages.enumerated() {
            let path: String = "$.stages[\(index)]"
            let pageID: String = try Self.nonempty(stage.pageID, path: "\(path).pageID")
            let key = StageKey(pageID: pageID, stage: stage.stage)
            guard stageKeys.insert(key).inserted else {
                throw Self.invalid(path, "duplicates a page/stage record")
            }
            guard stage.sampleCount >= 0 else {
                throw Self.invalid("\(path).sampleCount", "must be nonnegative")
            }

            if stage.stage == .playback {
                guard playbackPageIDs.insert(pageID).inserted else {
                    throw Self.invalid(path, "duplicates a playback page")
                }
                guard let playback: VideoRuntimePlaybackEvidenceV2 = stage.playback else {
                    throw Self.invalid("\(path).playback", "is required")
                }
                guard stage.branch == .playback,
                      stage.environment == .browseCraftApp,
                      stage.runtimeEquivalent else {
                    throw Self.invalid(path, "playback must use the BrowseCraft App runtime")
                }
                // 中文注释：BC-EVIDENCE-079.1——resolvedNeedsWebView 是 catalog 静态解析，route 是实际
                // 最终路线（到达 WebUI 即 webkit）；只要求静态需要 WebView 时路线必为 webkit。
                guard stage.resolvedNeedsWebView == false || stage.route == .webKit else {
                    throw Self.invalid(path, "resolvedNeedsWebView requires route=webkit")
                }
                guard let contract = self.playbackContracts[pageID] else {
                    throw Self.invalid(path, "has no prepared playback export contract")
                }
                try self.validatePlayback(
                    playback,
                    stage: stage,
                    contract: contract,
                    path: "\(path).playback"
                )
            } else {
                guard stage.playback == nil else {
                    throw Self.invalid("\(path).playback", "is only allowed for playback")
                }
                guard stage.branch != .playback else {
                    throw Self.invalid("\(path).branch", "is invalid for a data stage")
                }
            }
        }

        guard playbackPageIDs == Set(self.playbackContracts.keys) else {
            throw Self.invalid(
                "$.stages",
                "playback stages do not exactly match prepared playback contracts"
            )
        }
    }

    private func validatePlayback(
        _ playback: VideoRuntimePlaybackEvidenceV2,
        stage: VideoRuntimeStageEvidenceV2,
        contract: VideoRuntimePlaybackExportContract,
        path: String
    ) throws {
        let selectedFingerprint = try self.validateSampleSelection(
            playback.sampleSelection,
            detailReadyApplicable: contract.detailReadyApplicable,
            groupTitleApplicable: playback.expectedGroupOwnerIDs.count > 1,
            path: "\(path).sampleSelection"
        )
        try self.validateExpectedGroupOwners(
            playback.expectedGroupOwnerIDs,
            pageID: stage.pageID,
            path: "\(path).expectedGroupOwnerIDs"
        )
        guard playback.routes.count == stage.sampleCount else {
            throw Self.invalid("\(path).routes", "count must equal stage sampleCount")
        }
        guard playback.routes.count <= Self.maximumGroupOwners * Self.maximumSamplesPerGroup else {
            throw Self.invalid("\(path).routes", "exceeds safety limit")
        }

        let groupPositions: [String: Int] = Dictionary(
            uniqueKeysWithValues: playback.expectedGroupOwnerIDs.enumerated().map { offset, owner in
                (owner, offset + 1)
            }
        )
        var sampleCounts: [String: Int] = Dictionary(
            uniqueKeysWithValues: playback.expectedGroupOwnerIDs.map { ($0, 0) }
        )
        var priorSamples: [String: (passed: Bool, routeFingerprints: [VideoRuntimeEvidenceFingerprint])] = [:]
        var expectedOrder: [(Int, Int)] = []

        for (index, route) in playback.routes.enumerated() {
            let routePath: String = "\(path).routes[\(index)]"
            guard route.detailSampleFingerprint == selectedFingerprint else {
                throw Self.invalid("\(routePath).detailSampleFingerprint", "does not bind selected Detail")
            }
            guard let expectedGroupIndex: Int = groupPositions[route.groupOwnerID],
                  route.groupIndex == expectedGroupIndex else {
                throw Self.invalid(routePath, "groupOwnerID and groupIndex disagree")
            }
            let expectedSampleIndex: Int = (sampleCounts[route.groupOwnerID] ?? 0) + 1
            guard route.sampleIndex == expectedSampleIndex,
                  (1...Self.maximumSamplesPerGroup).contains(route.sampleIndex) else {
                throw Self.invalid("\(routePath).sampleIndex", "must increase continuously from 1")
            }
            sampleCounts[route.groupOwnerID] = route.sampleIndex
            expectedOrder.append((route.groupIndex, route.sampleIndex))
            try self.validateRoute(
                route,
                contract: contract,
                path: routePath
            )
            let fingerprints: [VideoRuntimeEvidenceFingerprint] = route.routeAttempts.map(\.routeFingerprint)
            let passed: Bool = route.routeAttempts.contains(where: \.passed)
            if let prior = priorSamples[route.groupOwnerID],
               prior.passed,
               prior.routeFingerprints == fingerprints {
                throw Self.invalid(routePath, "prior stable route sample already passed")
            }
            priorSamples[route.groupOwnerID] = (passed, fingerprints)
        }

        let sortedOrder: [(Int, Int)] = expectedOrder.sorted(by: Self.groupSampleOrder)
        guard zip(expectedOrder, sortedOrder).allSatisfy({ actual, expected in
            actual.0 == expected.0 && actual.1 == expected.1
        }) else {
            throw Self.invalid("\(path).routes", "must be ordered by group then sampleIndex")
        }
        guard sampleCounts.values.allSatisfy({ $0 > 0 }) else {
            throw Self.invalid("\(path).routes", "is missing a required group sample")
        }
        let independentlyPassingGroups: Set<String> = self.independentlyPassingGroupOwners(
            playback.routes
        )
        let allGroupsPassed: Bool = playback.expectedGroupOwnerIDs.allSatisfy { ownerID in
            independentlyPassingGroups.contains(ownerID)
        }
        let selectedAttempt = playback.sampleSelection.attempts[
            playback.sampleSelection.selectedAttempt - 1
        ]
        guard selectedAttempt.playbackPassed == allGroupsPassed else {
            throw Self.invalid(path, "selected Detail playbackPassed disagrees with group routes")
        }
        if stage.coverageComplete && allGroupsPassed == false {
            throw Self.invalid(path, "coverageComplete requires every group to pass")
        }
        if stage.passed && (stage.coverageComplete == false || allGroupsPassed == false) {
            throw Self.invalid(path, "passed requires complete independently safe group routes")
        }
    }

    private func validateSampleSelection(
        _ selection: VideoRuntimeDetailSampleSelectionEvidence,
        detailReadyApplicable: Bool,
        groupTitleApplicable: Bool,
        path: String
    ) throws -> VideoRuntimeEvidenceFingerprint {
        guard (1...Self.maximumDetailAttempts).contains(selection.maximumAttempts) else {
            throw Self.invalid("\(path).maximumAttempts", "must be in 1...3")
        }
        guard (1...selection.maximumAttempts).contains(selection.attemptedCount),
              selection.attemptedCount == selection.attempts.count else {
            throw Self.invalid("\(path).attemptedCount", "must equal attempts count within the maximum")
        }
        guard (1...selection.attemptedCount).contains(selection.selectedAttempt) else {
            throw Self.invalid("\(path).selectedAttempt", "does not reference an attempt")
        }

        let scores: [Int] = try selection.attempts.enumerated().map { offset, attempt in
            let attemptPath: String = "\(path).attempts[\(offset)]"
            guard attempt.attempt == offset + 1 else {
                throw Self.invalid("\(attemptPath).attempt", "must be continuous and 1-based")
            }
            return Self.score(
                attempt,
                detailReadyApplicable: detailReadyApplicable,
                groupTitleApplicable: groupTitleApplicable
            )
        }
        if let firstCompleteIndex: Int = scores.firstIndex(of: 7) {
            let firstCompleteAttempt: Int = firstCompleteIndex + 1
            guard selection.selectedAttempt == firstCompleteAttempt,
                  selection.attemptedCount == firstCompleteAttempt else {
                throw Self.invalid(path, "must select the first complete chain and stop")
            }
        } else if let bestScore: Int = scores.max(),
                  let earliestBestIndex: Int = scores.firstIndex(of: bestScore) {
            guard selection.selectedAttempt == earliestBestIndex + 1 else {
                throw Self.invalid(path, "must select the earliest best incomplete chain")
            }
        }
        return selection.attempts[selection.selectedAttempt - 1].detailSampleFingerprint
    }

    private func validateExpectedGroupOwners(
        _ owners: [String],
        pageID: String,
        path: String
    ) throws {
        guard owners.isEmpty == false,
              owners.count <= Self.maximumGroupOwners,
              Set(owners).count == owners.count else {
            throw Self.invalid(path, "must contain 1...100 unique owners")
        }
        for (offset, owner) in owners.enumerated() {
            let expected: String = try VideoRuntimeEvidenceFingerprintFactory.groupOwnerID(
                pageID: pageID,
                groupIndex: offset + 1
            )
            guard owner == expected else {
                throw Self.invalid("\(path)[\(offset)]", "must equal \(expected)")
            }
        }
    }

    private func validateRoute(
        _ route: VideoRuntimePlaybackRouteEvidence,
        contract: VideoRuntimePlaybackExportContract,
        path: String
    ) throws {
        guard route.routeAttempts.count == contract.declaredRoutes.count else {
            throw Self.invalid("\(path).routeAttempts", "does not cover every declared route")
        }
        let actualContracts: [VideoRuntimeDeclaredRouteContract] = route.routeAttempts.map { attempt in
            VideoRuntimeDeclaredRouteContract(
                routeSlot: attempt.routeSlot,
                executionMode: attempt.executionMode
            )
        }
        guard actualContracts == contract.declaredRoutes else {
            throw Self.invalid("\(path).routeAttempts", "does not match declared route order and mode")
        }
        guard Set(route.routeAttempts.map(\.routeFingerprint)).count == route.routeAttempts.count else {
            throw Self.invalid("\(path).routeAttempts", "route fingerprints must be unique per slot")
        }

        var priorRoutePassed: Bool = false
        var passedSlots: [VideoRuntimeEvidenceRouteSlot] = []
        var rejectedHLSRouteFingerprints: Set<VideoRuntimeEvidenceFingerprint> = []
        var rejectedHLSMediaFingerprints: Set<VideoRuntimeEvidenceFingerprint> = []
        for (index, attempt) in route.routeAttempts.enumerated() {
            let attemptPath: String = "\(path).routeAttempts[\(index)]"
            try self.validateAttempt(
                attempt,
                declaredMediaKind: contract.declaredMediaKind,
                path: attemptPath
            )
            if priorRoutePassed && attempt.attempted {
                throw Self.invalid(attemptPath, "must not execute after a prior route passed")
            }
            if attempt.attempted == false && priorRoutePassed == false {
                throw Self.invalid(attemptPath, "cannot skip before a prior route passed")
            }
            if attempt.passed {
                guard rejectedHLSRouteFingerprints.contains(attempt.routeFingerprint) == false,
                      attempt.resolvedMediaFingerprint.map(
                          { rejectedHLSMediaFingerprints.contains($0) == false }
                      ) == true else {
                    throw Self.invalid(attemptPath, "reuses a rejected HLS identity")
                }
                passedSlots.append(attempt.routeSlot)
                priorRoutePassed = true
            }
            // 中文注释：BC-EVIDENCE-026——只有明确 encrypted 反向否决同 fingerprint；
            // unknown 失败样本不污染同 fingerprint 的其他样本。
            if attempt.attempted,
               attempt.passed == false,
               attempt.resolvedMediaKind == .hls,
               attempt.encryptionStatus == .encrypted {
                rejectedHLSRouteFingerprints.insert(attempt.routeFingerprint)
                if let mediaFingerprint = attempt.resolvedMediaFingerprint {
                    rejectedHLSMediaFingerprints.insert(mediaFingerprint)
                }
            }
        }
        guard passedSlots.count <= 1 else {
            throw Self.invalid(path, "has more than one passing route")
        }
        if let passedSlot = passedSlots.first {
            guard route.selectedRouteSlot == passedSlot else {
                throw Self.invalid("\(path).selectedRouteSlot", "must identify the passing route")
            }
        } else if route.selectedRouteSlot != nil {
            throw Self.invalid("\(path).selectedRouteSlot", "requires a passing route")
        }
    }

    private func validateAttempt(
        _ attempt: VideoRuntimeRouteAttemptEvidence,
        declaredMediaKind: VideoRuntimeEvidenceMediaKind?,
        path: String
    ) throws {
        guard Self.executionMode(attempt.executionMode, matches: attempt.routeSlot) else {
            throw Self.invalid(path, "executionMode does not match routeSlot")
        }
        if attempt.attempted == false {
            guard attempt.passed == false,
                  attempt.skipReason == .priorRouteSelected,
                  Self.hasAttemptResultFields(attempt) == false else {
                throw Self.invalid(path, "skipped route contains invalid conditional fields")
            }
            return
        }

        guard attempt.skipReason == nil,
              let mediaKind = attempt.resolvedMediaKind,
              let binding = attempt.resolvedMediaBinding,
              let encryptionStatus = attempt.encryptionStatus else {
            throw Self.invalid(path, "attempted route is missing media result fields")
        }
        guard binding.method == Self.bindingMethod(for: attempt.executionMode) else {
            throw Self.invalid("\(path).resolvedMediaBinding.method", "does not match executionMode")
        }
        if binding.status == .unique {
            guard binding.ownerFingerprint != nil else {
                throw Self.invalid("\(path).resolvedMediaBinding.ownerFingerprint", "is required")
            }
        } else {
            guard binding.ownerFingerprint == nil,
                  mediaKind == .unknown,
                  attempt.passed == false else {
                throw Self.invalid(path, "ambiguous/missing binding must fail as unknown")
            }
        }
        guard Self.encryptionStatus(encryptionStatus, matches: mediaKind) else {
            throw Self.invalid("\(path).encryptionStatus", "does not match media kind")
        }

        switch mediaKind {
        case .unknown:
            guard attempt.resolvedMediaFingerprint == nil,
                  attempt.mediaResponsePassed == nil,
                  attempt.bytesRead == nil,
                  attempt.contentType == nil,
                  attempt.manifestPassed == nil,
                  attempt.firstMediaReferencePassed == nil,
                  attempt.passed == false else {
                throw Self.invalid(path, "unknown media contains media success fields")
            }
        case .hls, .mp4:
            guard binding.status == .unique,
                  attempt.resolvedMediaFingerprint != nil,
                  attempt.mediaResponsePassed == true,
                  let bytesRead = attempt.bytesRead,
                  bytesRead > 0,
                  let contentType = attempt.contentType,
                  Self.contentType(contentType, matches: mediaKind) else {
                throw Self.invalid(path, "known media is missing a valid native response")
            }
            if mediaKind == .hls {
                guard attempt.manifestPassed == true,
                      attempt.firstMediaReferencePassed == true else {
                    throw Self.invalid(path, "HLS manifest evidence is incomplete")
                }
                if attempt.routeSlot == .media,
                   let declaredMediaKind = declaredMediaKind,
                   declaredMediaKind != .hls {
                    throw Self.invalid(path, "media kind does not match the Catalog media route")
                }
            } else {
                guard attempt.manifestPassed == nil,
                      attempt.firstMediaReferencePassed == nil else {
                    throw Self.invalid(path, "MP4 must not contain HLS manifest fields")
                }
                if attempt.routeSlot == .media,
                   let declaredMediaKind = declaredMediaKind,
                   declaredMediaKind != .mp4 {
                    throw Self.invalid(path, "media kind does not match the Catalog media route")
                }
            }
        }

        if attempt.executionMode == .webUI {
            guard let playerStarted = attempt.playerStarted,
                  attempt.passed == false || playerStarted else {
                throw Self.invalid("\(path).playerStarted", "is required and must be true on pass")
            }
        } else if attempt.playerStarted != nil {
            throw Self.invalid("\(path).playerStarted", "is only valid for WebUI")
        }

        if attempt.passed {
            // 中文注释：BC-EVIDENCE-022/029——HLS 只有明确 encrypted 才不得通过；unknown 在
            // manifest/首媒体引用/bytes 证据齐备时可通过，且必须保持 unknown 不改写。
            guard attempt.rejectionReason == nil,
                  mediaKind != .unknown,
                  mediaKind != .hls || encryptionStatus != .encrypted else {
                throw Self.invalid(path, "passing route is not independently safe")
            }
        } else if attempt.rejectionReason == nil {
            throw Self.invalid("\(path).rejectionReason", "is required for a failed attempt")
        }
    }

    private func independentlyPassingGroupOwners(
        _ routes: [VideoRuntimePlaybackRouteEvidence]
    ) -> Set<String> {
        let grouped: [String: [VideoRuntimePlaybackRouteEvidence]] = Dictionary(
            grouping: routes,
            by: \.groupOwnerID
        )
        var passingGroups: Set<String> = []
        for (ownerID, groupRoutes) in grouped {
            let attempts: [VideoRuntimeRouteAttemptEvidence] = groupRoutes.flatMap(\.routeAttempts)
            // 中文注释：BC-EVIDENCE-026——跨样本媒体身份归约同样只以明确 encrypted 为毒化条件；
            // unknown 本身不污染，同 fingerprint 一旦被任一样本判为 encrypted 才整体否决。
            let rejectedHLSMedia: Set<VideoRuntimeEvidenceFingerprint> = Set(
                attempts.compactMap { attempt in
                    guard attempt.attempted,
                          attempt.passed == false,
                          attempt.resolvedMediaKind == .hls,
                          attempt.encryptionStatus == .encrypted else {
                        return nil
                    }
                    return attempt.resolvedMediaFingerprint
                }
            )
            let hasIndependentPass: Bool = attempts.contains { attempt in
                guard attempt.passed,
                      let mediaFingerprint = attempt.resolvedMediaFingerprint else {
                    return false
                }
                return rejectedHLSMedia.contains(mediaFingerprint) == false
            }
            if hasIndependentPass {
                passingGroups.insert(ownerID)
            }
        }
        return passingGroups
    }

    private static func validateDeclaredRoutes(
        _ contract: VideoRuntimePlaybackExportContract,
        path: String
    ) throws {
        guard contract.declaredRoutes.isEmpty == false,
              contract.declaredRoutes.count <= VideoRuntimeEvidenceRouteSlot.allCases.count else {
            throw Self.invalid("\(path).declaredRoutes", "must contain 1...3 routes")
        }
        let slots: [VideoRuntimeEvidenceRouteSlot] = contract.declaredRoutes.map(\.routeSlot)
        guard Set(slots).count == slots.count,
              slots.map(\.order) == slots.map(\.order).sorted() else {
            throw Self.invalid("\(path).declaredRoutes", "must be unique and ordered")
        }
        for route in contract.declaredRoutes {
            guard Self.executionMode(route.executionMode, matches: route.routeSlot) else {
                throw Self.invalid("\(path).declaredRoutes", "contains an invalid slot/mode pair")
            }
        }
        if slots.contains(.media) {
            guard contract.declaredMediaKind == .hls || contract.declaredMediaKind == .mp4 else {
                throw Self.invalid("\(path).declaredMediaKind", "is required for a media route")
            }
        } else if contract.declaredMediaKind != nil {
            throw Self.invalid("\(path).declaredMediaKind", "requires a media route")
        }
    }

    private static func score(
        _ attempt: VideoRuntimeDetailSampleAttemptEvidence,
        detailReadyApplicable: Bool,
        groupTitleApplicable: Bool
    ) -> Int {
        var score: Int = [
            attempt.detailPassed,
            attempt.detailTitlePassed,
            attempt.detailCoverPassed,
            attempt.episodePassed,
            attempt.playbackPassed
        ].filter { $0 }.count
        score += Self.qualityStatusPasses(
            attempt.detailReadyStatus,
            applicable: detailReadyApplicable
        ) ? 1 : 0
        score += Self.qualityStatusPasses(
            attempt.episodeGroupTitleStatus,
            applicable: groupTitleApplicable
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

    private static func executionMode(
        _ mode: VideoRuntimeEvidenceExecutionMode,
        matches slot: VideoRuntimeEvidenceRouteSlot
    ) -> Bool {
        switch slot {
        case .media:
            return mode == .directMedia
        case .iframe:
            return mode == .iframeResolve || mode == .webUI
        case .fallback:
            return mode == .webUI
        }
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

    private static func encryptionStatus(
        _ status: VideoRuntimeEvidenceEncryptionStatus,
        matches kind: VideoRuntimeEvidenceMediaKind
    ) -> Bool {
        switch kind {
        case .hls:
            return status == .unencrypted || status == .encrypted || status == .unknown
        case .mp4:
            return status == .notApplicable
        case .unknown:
            return status == .unknown
        }
    }

    private static func contentType(
        _ contentType: String,
        matches kind: VideoRuntimeEvidenceMediaKind
    ) -> Bool {
        let mediaType: Substring = contentType
            .lowercased()
            .split(separator: ";", maxSplits: 1)
            .first ?? ""
        let value: String = String(mediaType)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .hls:
            return value.contains("mpegurl") || value.contains("m3u8")
        case .mp4:
            // 中文注释：BC-EVIDENCE-079.6——与探针同一判定：mp4 或 octet-stream（ftyp 已由探针校验）。
            return VideoRuntimeAuditMediaProbe.contentTypeAllowsMP4(contentType)
        case .unknown:
            return false
        }
    }

    private static func hasAttemptResultFields(
        _ attempt: VideoRuntimeRouteAttemptEvidence
    ) -> Bool {
        return attempt.resolvedMediaKind != nil
            || attempt.resolvedMediaFingerprint != nil
            || attempt.resolvedMediaBinding != nil
            || attempt.encryptionStatus != nil
            || attempt.mediaResponsePassed != nil
            || attempt.bytesRead != nil
            || attempt.contentType != nil
            || attempt.manifestPassed != nil
            || attempt.firstMediaReferencePassed != nil
            || attempt.playerStarted != nil
            || attempt.rejectionReason != nil
    }

    private static func nonempty(_ value: String, path: String) throws -> String {
        let normalized: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw Self.invalid(path, "must not be empty")
        }
        return normalized
    }

    private static func groupSampleOrder(
        _ lhs: (Int, Int),
        _ rhs: (Int, Int)
    ) -> Bool {
        if lhs.0 != rhs.0 {
            return lhs.0 < rhs.0
        }
        return lhs.1 < rhs.1
    }

    private static func invalid(
        _ path: String,
        _ reason: String
    ) -> VideoRuntimeEvidenceExportError {
        return .invalid(path: path, reason: reason)
    }
}

private struct StageKey: Hashable {
    let pageID: String
    let stage: VideoRuntimeEvidenceStage
}
