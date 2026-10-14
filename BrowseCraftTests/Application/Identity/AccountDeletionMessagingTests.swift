import BrowseCraftAPIKit
import Foundation
import Testing
@testable import BrowseCraft

/// docs/design/Account-Deletion-Design.md 第八节：服务端代码到成因的对应，与「账号未删除」的提示原则。
struct AccountDeletionMessagingTests {
    @Test(arguments: [
        ("AUTH_ACCESS_TOKEN_EXPIRED", 401, AccountDeletionServiceError.sessionExpired),
        ("AUTH_APPLE_CHALLENGE_INVALID", 401, .verificationExpired),
        ("ACCOUNT_DELETION_APPLE_CODE_INVALID", 400, .verificationExpired),
        ("ACCOUNT_DELETION_APPLE_ACCOUNT_MISMATCH", 403, .appleAccountMismatch),
        ("ACCOUNT_DELETION_APPLE_UNAVAILABLE", 503, .appleUnavailable),
        ("ACCOUNT_DELETION_APPLE_NOT_CONFIGURED", 503, .notConfigured),
        ("ACCOUNT_DELETION_PERSISTENCE_ERROR", 500, .persistenceFailed),
        ("AUTH_RATE_LIMITED", 429, .rateLimited),
        ("ACCOUNT_INVALID_REQUEST", 400, .rejected(code: "ACCOUNT_INVALID_REQUEST"))
    ])
    func serverCodesMapToCauses(code: String, status: Int, expected: AccountDeletionServiceError) throws {
        let body: PortalAPIErrorBody = try JSONDecoder().decode(
            PortalAPIErrorBody.self,
            from: Data(#"{"code":"\#(code)","message":"","requestId":"r","details":{}}"#.utf8)
        )
        let error: PortalAPIError = .server(statusCode: status, body: body)
        #expect(APIKitPortalAccountDeletionService.map(error) == expected)
    }

    @Test func responsesWithoutAReadableOutcomeAreUnknown() {
        #expect(APIKitPortalAccountDeletionService.map(PortalAPIError.transportFailed) == .outcomeUnknown)
        #expect(APIKitPortalAccountDeletionService.map(PortalAPIError.responseDecodingFailed) == .outcomeUnknown)
        #expect(APIKitPortalAccountDeletionService.map(PortalAPIError.unexpectedStatusCode(502)) == .outcomeUnknown)
        #expect(APIKitPortalAccountDeletionService.map(PortalAPIError.unexpectedStatusCode(404)) == .rejected(code: "HTTP_404"))
    }

    @MainActor
    @Test func everyNotDeletedFailureSaysAccountNotDeleted() {
        let notDeleted: String = NSLocalizedString("account_deletion_failed_title", comment: "")
        let failures: [AccountDeletionError] = [
            .reauthenticationFailed, .sessionExpired, .verificationExpired, .appleAccountMismatch,
            .appleUnavailable, .notConfigured, .persistenceFailed, .rateLimited, .network, .failed
        ]
        for failure: AccountDeletionError in failures {
            #expect(AccountDeletionViewModel.alert(for: failure)?.title == notDeleted)
        }
        #expect(AccountDeletionViewModel.alert(for: .reauthenticationCancelled) == nil)
        #expect(AccountDeletionViewModel.alert(for: .outcomeUnknown)?.title != notDeleted)
    }

    @MainActor
    @Test func completionNotesFollowOutcome() {
        let clean: AccountDeletionOutcome = AccountDeletionOutcome(
            appleRevocationFailed: false, localCleanup: .done, cloudCleanup: .done
        )
        let messy: AccountDeletionOutcome = AccountDeletionOutcome(
            appleRevocationFailed: true, localCleanup: .reinstallRequired, cloudCleanup: .pending
        )
        #expect(AccountDeletionViewModel.completionNotes(for: clean).isEmpty)
        #expect(AccountDeletionViewModel.completionNotes(for: messy).count == 3)
    }

    @MainActor
    @Test func failedDeletionReturnsToExplanationWithAlert() async {
        let viewModel: AccountDeletionViewModel = AccountDeletionViewModel(
            coinBalance: { 120 },
            deleteAction: { throw AccountDeletionError.persistenceFailed }
        )

        await viewModel.confirmDeletion()

        #expect(viewModel.phase == .explaining)
        #expect(viewModel.failureAlert?.message == NSLocalizedString("account_deletion_error_persistence", comment: ""))
    }
}
