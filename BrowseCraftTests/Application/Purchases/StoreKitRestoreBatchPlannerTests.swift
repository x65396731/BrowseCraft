import Foundation
import Testing
@testable import BrowseCraft

/// docs/design/Account-Deletion-Design.md 第 9.1 节：恢复购买按 appAccountToken 分批，外来批被判属于别的账号时跳过。
@MainActor
struct StoreKitRestoreBatchPlannerTests {
    private struct Item: Equatable {
        let id: String
        let token: UUID?
    }

    private let userID: UUID = UUID()
    private let deletedAccount: UUID = UUID()
    private let livingAccount: UUID = UUID()

    @Test func ownBatchComesFirstAndEachForeignTokenGetsItsOwnBatch() {
        let items: [Item] = [
            Item(id: "a", token: self.deletedAccount),
            Item(id: "b", token: self.userID),
            Item(id: "c", token: nil),
            Item(id: "d", token: self.deletedAccount),
            Item(id: "e", token: self.livingAccount),
            Item(id: "f", token: self.userID)
        ]

        let plan = StoreKitRestoreBatchPlanner.plan(items, userID: self.userID, token: \.token)

        #expect(plan.startsWithOwnBatch)
        #expect(plan.missingTokenCount == 1)
        #expect(plan.batches.first?.map(\.id) == ["b", "f"])
        let foreign: Set<[String]> = Set(plan.batches.dropFirst().map { $0.map(\.id) })
        #expect(foreign == [["a", "d"], ["e"]])
    }

    @Test func foreignBatchRejectedAsOtherOwnerIsSkippedWithoutAbortingOthers() async throws {
        let items: [Item] = [
            Item(id: "own", token: self.userID),
            Item(id: "deleted", token: self.deletedAccount),
            Item(id: "living", token: self.livingAccount)
        ]
        let plan = StoreKitRestoreBatchPlanner.plan(items, userID: self.userID, token: \.token)
        let livingAccount: UUID = self.livingAccount
        var submitted: [[String]] = []

        let outcome = try await StoreKitRestoreBatchPlanner.run(
            plan,
            submit: { batch in
                submitted.append(batch.map(\.id))
                if batch.contains(where: { $0.token == livingAccount }) {
                    throw PortalIAPServiceError.accountMismatch
                }
                return Set(submitted.flatMap { $0 }.filter { $0 != "living" })
            },
            isForeignOwnerRejection: { error in
                return (error as? PortalIAPServiceError) == .accountMismatch
            }
        )

        #expect(submitted.count == 3)
        #expect(outcome.foreignItemCount == 1)
        #expect(outcome.submittedBatchIndexes.count == 2)
        #expect(outcome.submittedBatchIndexes.contains(0))
        #expect(outcome.activeProductIDs == ["own", "deleted"])
    }

    @Test func ownBatchRejectionStillThrows() async {
        let plan = StoreKitRestoreBatchPlanner.plan(
            [Item(id: "own", token: self.userID)],
            userID: self.userID,
            token: \.token
        )

        await #expect(throws: PortalIAPServiceError.accountMismatch) {
            _ = try await StoreKitRestoreBatchPlanner.run(
                plan,
                submit: { _ in throw PortalIAPServiceError.accountMismatch },
                isForeignOwnerRejection: { _ in true }
            )
        }
    }

    @Test func otherForeignErrorsStillThrow() async {
        let plan = StoreKitRestoreBatchPlanner.plan(
            [Item(id: "deleted", token: self.deletedAccount)],
            userID: self.userID,
            token: \.token
        )

        await #expect(throws: PortalIAPServiceError.temporarilyUnavailable) {
            _ = try await StoreKitRestoreBatchPlanner.run(
                plan,
                submit: { _ in throw PortalIAPServiceError.temporarilyUnavailable },
                isForeignOwnerRejection: { error in
                    return (error as? PortalIAPServiceError) == .accountMismatch
                }
            )
        }
    }

    @Test func onlyForeignBatchesAllSkippedLeavesNoEntitlements() async throws {
        let plan = StoreKitRestoreBatchPlanner.plan(
            [Item(id: "living", token: self.livingAccount), Item(id: "untagged", token: nil)],
            userID: self.userID,
            token: \.token
        )

        let outcome = try await StoreKitRestoreBatchPlanner.run(
            plan,
            submit: { _ in throw PortalIAPServiceError.transactionAlreadyClaimed },
            isForeignOwnerRejection: { _ in true }
        )

        #expect(plan.startsWithOwnBatch == false)
        #expect(outcome.activeProductIDs == nil)
        #expect(outcome.submittedBatchIndexes.isEmpty)
        #expect(outcome.foreignItemCount == 2)
    }
}
