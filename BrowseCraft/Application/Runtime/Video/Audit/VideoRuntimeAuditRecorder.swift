import Foundation

enum VideoRuntimeAuditRecorderError: Error, Equatable {
    case duplicateStage(pageID: String, stage: VideoRuntimeEvidenceStage)
    case duplicateBlockedCapability(VideoRuntimeEvidenceBlockedCapability)
}

// 中文注释：只有显式 audit session 才创建 recorder；正常播放不持久化或导出这些记录。
actor VideoRuntimeAuditRecorder {
    private let catalogSHA256: VideoRuntimeEvidenceFingerprint
    private var stages: [VideoRuntimeStageEvidenceV2] = []
    private var stageKeys: Set<StageKey> = []
    private var login: VideoRuntimeLoginEvidence?
    private var blockedCapabilities: [VideoRuntimeEvidenceBlockedCapability] = []
    private var blockedCapabilitySet: Set<VideoRuntimeEvidenceBlockedCapability> = []

    init(catalogInput: VideoRuntimeAuditCatalogInput) {
        self.catalogSHA256 = catalogInput.catalogSHA256
    }

    func record(_ stage: VideoRuntimeStageEvidenceV2) throws {
        let key = StageKey(pageID: stage.pageID, stage: stage.stage)
        guard self.stageKeys.insert(key).inserted else {
            throw VideoRuntimeAuditRecorderError.duplicateStage(
                pageID: stage.pageID,
                stage: stage.stage
            )
        }
        self.stages.append(stage)
    }

    func recordLogin(_ login: VideoRuntimeLoginEvidence) {
        self.login = login
    }

    func recordBlockedCapability(
        _ capability: VideoRuntimeEvidenceBlockedCapability
    ) throws {
        guard self.blockedCapabilitySet.insert(capability).inserted else {
            throw VideoRuntimeAuditRecorderError.duplicateBlockedCapability(capability)
        }
        self.blockedCapabilities.append(capability)
    }

    func snapshot() -> VideoRuntimeEvidenceV2 {
        return VideoRuntimeEvidenceV2(
            catalogSHA256: self.catalogSHA256,
            stages: self.stages,
            login: self.login,
            blockedCapabilities: self.blockedCapabilities
        )
    }
}

private struct StageKey: Hashable, Sendable {
    let pageID: String
    let stage: VideoRuntimeEvidenceStage
}
