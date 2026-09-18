import Foundation
import Testing
@testable import BrowseCraft

struct AppBootstrapFailureTests {
    private enum StubError: Error {
        case failed(secret: String)
    }

    /// 中文注释：声明了摘要的错误，只把自己允许外泄的那部分交出来。
    private enum DiagnosableStubError: Error, DiagnosticSummaryProviding {
        case rejected(status: Int32, secret: String)

        var diagnosticSummary: String {
            switch self {
            case .rejected(let status, _):
                return "rejected(\(status))"
            }
        }
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

    /// 中文注释：未声明摘要的错误，负载一律不进诊断信息——这是默认安全的那一半。
    @Test func diagnosticDetailOmitsThePayloadOfErrorsThatDeclareNoSummary() {
        let failure: AppBootstrapFailure = AppBootstrapFailure(
            error: StubError.failed(secret: "first-secret")
        )

        #expect(failure.diagnosticDetail.contains("first-secret") == false)
        #expect(failure.diagnosticDetail.contains("StubError"))
        #expect(failure.diagnosticDetail.contains("code="))
    }

    /// 中文注释：声明了摘要的错误，状态码必须可见——这正是此前拿到 BOOT-XXXX 也查不出原因的那一半。
    @Test func diagnosticDetailSurfacesTheSummaryAnErrorDeclares() {
        let failure: AppBootstrapFailure = AppBootstrapFailure(
            error: DiagnosableStubError.rejected(status: -34_018, secret: "first-secret")
        )

        #expect(failure.diagnosticDetail.contains("rejected(-34018)"))
        #expect(failure.diagnosticDetail.contains("first-secret") == false)
    }

    /// 中文注释：Keychain 身份存储的 OSStatus 是引导失败最常见的原因，单独守一条。
    @Test func keychainIdentityStoreErrorReportsItsOSStatus() {
        let failure: AppBootstrapFailure = AppBootstrapFailure(
            error: KeychainAppUserIdentityStoreError.unexpectedStatus(-34_018)
        )

        #expect(failure.diagnosticDetail.contains("unexpectedStatus(-34018)"))
        #expect(failure.copyableDiagnostics.contains(failure.diagnosticCode))
        #expect(failure.copyableDiagnostics.contains("unexpectedStatus(-34018)"))
    }
}
