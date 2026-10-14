import Foundation

/// 中文注释：恢复购买按 appAccountToken 分批（docs/design/Account-Deletion-Design.md 第 9.1 节）。
/// 服务端只放行「token 指向的账号已删除」的外来交易，且一批里只要有一笔属于仍存在的账号就整批拒绝，
/// 所以本账号的交易一批、每个外来 token 各一批；外来批被判属于别的账号时跳过，不连累其他批。
enum StoreKitRestoreBatchPlanner {
    struct Plan<Item> {
        /// 中文注释：本账号批在前，外来批按 token 字符串排序，保证顺序稳定。
        var batches: [[Item]]
        /// 中文注释：没有 appAccountToken 的交易不提交，计入「属于别的账号」。
        var missingTokenCount: Int
        /// 中文注释：第 0 批是否是本账号批；本账号批失败照旧整体报错。
        var startsWithOwnBatch: Bool
    }

    struct Outcome {
        /// 中文注释：最后一次成功提交时服务端回的完整权益；没有任何批成功时为 nil。
        var activeProductIDs: Set<String>?
        /// 中文注释：成功提交的批下标，调用方只 finish 这些批里的交易。
        var submittedBatchIndexes: [Int]
        /// 中文注释：被服务端判为属于别的账号而跳过的交易数（含没有 token 的）。
        var foreignItemCount: Int
    }

    static func plan<Item>(
        _ items: [Item],
        userID: UUID,
        token: (Item) -> UUID?
    ) -> Plan<Item> {
        var own: [Item] = []
        var foreign: [UUID: [Item]] = [:]
        var missingTokenCount: Int = 0
        for item: Item in items {
            guard let itemToken: UUID = token(item) else {
                missingTokenCount += 1
                continue
            }
            if itemToken == userID {
                own.append(item)
            } else {
                foreign[itemToken, default: []].append(item)
            }
        }
        let foreignBatches: [[Item]] = foreign
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map(\.value)
        return Plan(
            batches: (own.isEmpty ? [] : [own]) + foreignBatches,
            missingTokenCount: missingTokenCount,
            startsWithOwnBatch: own.isEmpty == false
        )
    }

    /// 中文注释：逐批提交。外来批遇到 `isForeignOwnerRejection` 判定的错误就跳过；其余错误照旧抛出。
    /// 只在 MainActor 上的恢复流程里用，提交闭包因此可以直接碰 MainActor 状态。
    @MainActor
    static func run<Item>(
        _ plan: Plan<Item>,
        submit: @MainActor ([Item]) async throws -> Set<String>,
        isForeignOwnerRejection: @MainActor (any Error) -> Bool
    ) async throws -> Outcome {
        var outcome: Outcome = Outcome(
            activeProductIDs: nil,
            submittedBatchIndexes: [],
            foreignItemCount: plan.missingTokenCount
        )
        for (index, batch) in plan.batches.enumerated() {
            let isOwnBatch: Bool = index == 0 && plan.startsWithOwnBatch
            do {
                outcome.activeProductIDs = try await submit(batch)
                outcome.submittedBatchIndexes.append(index)
            } catch where isOwnBatch == false && isForeignOwnerRejection(error) {
                outcome.foreignItemCount += batch.count
            }
        }
        return outcome
    }
}
