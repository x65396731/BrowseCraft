import Foundation

/// 中文注释：首次绑定只复制 local.default，不删除原空间；取消由调用方不执行 prepare 表示。
protocol CloudAccountPartitioning {
    func localDefaultSummary() throws -> CloudAccountPartitionSummary
    func prepareCloudScope(
        _ cloudScope: CloudAccountScope,
        decision: CloudAccountLocalDataDecision
    ) throws -> CloudAccountPartitionMergeResult
}
