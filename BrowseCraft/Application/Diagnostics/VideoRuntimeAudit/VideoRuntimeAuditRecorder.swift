// 中文注释：显式 runtime audit 只随 Debug 构建编译；Release/TestFlight 不含审计代码。
#if DEBUG
import BrowseCraftRuntime
import Foundation

enum VideoRuntimeAuditRecorderError: Error, Equatable {
    case duplicateStage(pageID: String, stage: VideoRuntimeEvidenceStage)
}

// 中文注释：只有显式 audit session 才创建 recorder；正常播放不持久化或导出这些记录。
actor VideoRuntimeAuditRecorder {
    private let catalogSHA256: VideoRuntimeEvidenceFingerprint
    private var stages: [VideoRuntimeStageEvidenceV2] = []
    private var stageKeys: Set<StageKey> = []
    private var login: VideoRuntimeLoginEvidence?

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

    func snapshot() -> VideoRuntimeEvidenceV2 {
        return VideoRuntimeEvidenceV2(
            catalogSHA256: self.catalogSHA256,
            stages: self.stages,
            login: self.login,
            // 中文注释：没有任何调用方记录过被挡能力（`recordBlockedCapability` 零引用，2026-10-20 删除），证据里恒为空。
            blockedCapabilities: []
        )
    }
}

private struct StageKey: Hashable, Sendable {
    let pageID: String
    let stage: VideoRuntimeEvidenceStage
}
#endif
