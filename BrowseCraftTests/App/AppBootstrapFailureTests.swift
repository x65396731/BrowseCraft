import Foundation
import Testing
@testable import BrowseCraft

struct AppBootstrapFailureTests {
    private enum StubError: Error {
        case failed(secret: String)
    }

    @Test func failureUsesStableCodeWithoutEmbeddingErrorPayload() {
        let first: AppBootstrapFailure = AppBootstrapFailure(
            error: StubError.failed(secret: "first-secret")
        )
        let second: AppBootstrapFailure = AppBootstrapFailure(
            error: StubError.failed(secret: "second-secret")
        )

        #expect(first.diagnosticCode == second.diagnosticCode)
        #expect(first.message.contains("first-secret") == false)
        #expect(first.recoverySuggestion.contains("first-secret") == false)
    }
}
