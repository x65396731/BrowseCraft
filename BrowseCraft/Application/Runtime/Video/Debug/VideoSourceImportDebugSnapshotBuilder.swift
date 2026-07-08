import Foundation
import BrowseCraftCore

struct VideoSourceImportDebugSnapshotBuilder {
    func makeSnapshot(
        source: Source,
        entryURL: URL,
        detection: VideoSourceDetection?,
        decision: VideoSourceImportDecision,
        startedAt: Date,
        completedAt: Date
    ) -> SourceDebugSnapshot {
        return SourceDebugSnapshot(
            id: "video-import.\(source.id)",
            startedAt: startedAt,
            completedAt: completedAt,
            input: SourceDebugInputSummary(
                sourceID: source.id,
                sourceName: source.name,
                operation: .debug,
                pageID: nil,
                tabID: nil,
                ruleID: nil,
                keyword: nil,
                page: nil,
                url: entryURL.absoluteString
            ),
            sourceKind: .video,
            structure: self.structureSummary(source: source, detection: detection, decision: decision),
            importDecision: self.importDecisionSummary(decision),
            signals: self.signals(source: source, detection: detection, decision: decision),
            requestLogs: [],
            extractionLogs: [],
            previewItems: [],
            issues: self.issues(decision: decision),
            status: self.status(decision: decision)
        )
    }

    private func structureSummary(
        source: Source,
        detection: VideoSourceDetection?,
        decision: VideoSourceImportDecision
    ) -> SourceDebugStructureSummary {
        guard let detection: VideoSourceDetection else {
            return SourceDebugStructureSummary(
                kind: .unknown,
                adapterID: nil,
                renderMode: nil,
                playbackMode: nil,
                confidence: nil
            )
        }

        return SourceDebugStructureSummary(
            kind: self.structureKind(detection: detection, decision: decision),
            adapterID: self.selectedAdapterID(source: source),
            renderMode: detection.renderMode.rawValue,
            playbackMode: detection.playbackMode.rawValue,
            confidence: detection.confidence
        )
    }

    private func structureKind(
        detection: VideoSourceDetection,
        decision: VideoSourceImportDecision
    ) -> SourceDebugStructureKind {
        switch decision {
        case .pluginRequired:
            return .pluginRequired
        case .unavailable(.lowConfidence):
            return .lowConfidence
        case .unavailable(.unknownStructure), .unavailable(.noVideoSignals):
            return .unknown
        case .unavailable(.unsupportedAdapter):
            return .unsupported
        case .supported, .needsReview:
            break
        }

        if detection.renderMode == .webViewRequired {
            return .webViewRequired
        }

        if detection.playbackMode == .iframePlayer {
            return .iframePlayer
        }

        switch self.adapter(from: decision) {
        case .macCMS?:
            return .macCMS
        case .genericHTML?:
            return .genericHTML
        case .webView?:
            return .webViewRequired
        case .plugin?:
            return .pluginRequired
        case nil:
            return .unknown
        }
    }

    private func importDecisionSummary(
        _ decision: VideoSourceImportDecision
    ) -> SourceDebugImportDecision {
        switch decision {
        case .supported:
            return SourceDebugImportDecision(branch: .saved, reason: nil)
        case .needsReview(_, let warnings):
            return SourceDebugImportDecision(
                branch: .needsReview,
                reason: warnings.first,
                warnings: warnings
            )
        case .unavailable(let reason):
            return SourceDebugImportDecision(
                branch: .unavailable,
                reason: reason.rawValue
            )
        case .pluginRequired(let reason):
            return SourceDebugImportDecision(
                branch: .pluginRequired,
                reason: reason.rawValue
            )
        }
    }

    private func signals(
        source: Source,
        detection: VideoSourceDetection?,
        decision: VideoSourceImportDecision
    ) -> [SourceDebugSignal] {
        var signals: [SourceDebugSignal] = []

        if let selectedAdapterID: String = self.selectedAdapterID(source: source) {
            signals.append(
                SourceDebugSignal(
                    id: "video.selectedAdapter",
                    category: .adapter,
                    key: "selectedAdapter",
                    value: selectedAdapterID
                )
            )
        }

        if let detection: VideoSourceDetection {
            signals.append(
                SourceDebugSignal(
                    id: "video.renderMode",
                    category: .structure,
                    key: "renderMode",
                    value: detection.renderMode.rawValue
                )
            )
            signals.append(
                SourceDebugSignal(
                    id: "video.playbackMode",
                    category: .structure,
                    key: "playbackMode",
                    value: detection.playbackMode.rawValue
                )
            )
            signals.append(contentsOf: self.reasonSignals(detection.reasons))
            signals.append(contentsOf: self.warningSignals(detection.warnings))
        } else {
            signals.append(
                SourceDebugSignal(
                    id: "video.detection.missingHTML",
                    category: .warning,
                    key: "detection",
                    value: "Entry HTML was not provided."
                )
            )
        }

        signals.append(
            SourceDebugSignal(
                id: "video.importDecision",
                category: .decision,
                key: "branch",
                value: self.importDecisionSummary(decision).branch.rawValue
            )
        )

        return signals
    }

    private func selectedAdapterID(source: Source) -> String? {
        guard case .video(let configuration) = source.configuration else {
            return nil
        }

        return configuration.definition.adapter.rawValue
    }

    private func adapter(from decision: VideoSourceImportDecision) -> VideoAdapter? {
        switch decision {
        case .supported(let definition), .needsReview(let definition, _):
            return definition.adapter
        case .unavailable, .pluginRequired:
            return nil
        }
    }

    private func reasonSignals(_ reasons: [String]) -> [SourceDebugSignal] {
        return reasons.enumerated().map { index, reason in
            SourceDebugSignal(
                id: "video.reason.\(index)",
                category: .structure,
                key: "reason",
                value: reason
            )
        }
    }

    private func warningSignals(_ warnings: [String]) -> [SourceDebugSignal] {
        return warnings.enumerated().map { index, warning in
            SourceDebugSignal(
                id: "video.warning.\(index)",
                category: .warning,
                key: "warning",
                value: warning
            )
        }
    }

    private func issues(decision: VideoSourceImportDecision) -> [SourceDebugIssue] {
        switch decision {
        case .supported:
            return []
        case .needsReview(_, let warnings):
            return warnings.enumerated().map { index, warning in
                SourceDebugIssue(
                    id: "video.needsReview.\(index)",
                    severity: .warning,
                    category: .importDecision,
                    operation: .debug,
                    ruleID: nil,
                    field: nil,
                    message: warning
                )
            }
        case .unavailable(let reason):
            return [
                SourceDebugIssue(
                    id: "video.unavailable.\(reason.rawValue)",
                    severity: .warning,
                    category: self.issueCategory(reason),
                    operation: .debug,
                    ruleID: nil,
                    field: nil,
                    message: reason.rawValue
                )
            ]
        case .pluginRequired(let reason):
            return [
                SourceDebugIssue(
                    id: "video.pluginRequired.\(reason.rawValue)",
                    severity: .warning,
                    category: .missingCapability,
                    operation: .debug,
                    ruleID: nil,
                    field: nil,
                    message: reason.rawValue
                )
            ]
        }
    }

    private func issueCategory(
        _ reason: VideoSourceUnavailableReason
    ) -> SourceDebugIssueCategory {
        switch reason {
        case .unknownStructure, .noVideoSignals:
            return .structureDetection
        case .lowConfidence:
            return .lowConfidence
        case .unsupportedAdapter:
            return .unsupportedStructure
        }
    }

    private func status(decision: VideoSourceImportDecision) -> SourceDebugStatus {
        switch decision {
        case .supported:
            return .succeeded
        case .needsReview:
            return .empty
        case .unavailable, .pluginRequired:
            return .failed
        }
    }
}
