import Foundation

/// 个人生成结果的读取结果：未登录与「登录了但为空」要分开呈现。
enum VideoGenerationOutcomesLoad: Hashable, Sendable {
    case authRequired
    case loaded([VideoGenerationOutcome])
    case failed(code: String)
}

/// 读取当前用户的规则生成终态（`BC-PREFLIGHT-056`）。
///
/// 中文注释：与任务提交共用同一凭据来源；没有有效 access token 时不发请求，直接返回
/// `authRequired`——「我的生成」分组据此显示登录提示而不是空列表。
struct LoadVideoGenerationOutcomesUseCase: Sendable {
    private let outcomesClient: any VideoGenerationOutcomesFetching
    private let accessTokenProvider: any PortalAccessTokenProviding

    init(
        outcomesClient: any VideoGenerationOutcomesFetching,
        accessTokenProvider: any PortalAccessTokenProviding
    ) {
        self.outcomesClient = outcomesClient
        self.accessTokenProvider = accessTokenProvider
    }

    func execute() async -> VideoGenerationOutcomesLoad {
        guard let accessToken: String = await self.accessTokenProvider.validAccessToken() else {
            return .authRequired
        }
        do {
            let outcomes: [VideoGenerationOutcome] = try await self.outcomesClient.fetchOutcomes(
                accessToken: accessToken
            )
            return .loaded(outcomes)
        } catch let error as VideoGenerationOutcomesClientError {
            switch error {
            case .authRequired:
                return .authRequired
            case .server(let code):
                return .failed(code: code)
            case .transport:
                return .failed(code: "transport")
            }
        } catch is CancellationError {
            return .failed(code: "cancelled")
        } catch {
            return .failed(code: AppLog.safeErrorCode(error))
        }
    }
}
