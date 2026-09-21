import BrowseCraftDomain
import Foundation

/// 一次已终结的规则生成任务（PortalCore `GET /v1/rule-generations/outcomes`，`BC-PREFLIGHT-056`）。
///
/// 中文注释：`reason` / `reasonDetail` 保持服务端的原始取值，文案映射放在 Feature 层——
/// 服务端会先于 App 上线新成因，App 不能因为没见过的值解码失败或误判。
/// `expiresAt` 是服务端给的本人可见期截止（终结 + 7 天）；`source` 是成功任务附带的加密规则，
/// 个人规则不再出现在公共目录，`catalogSource` 由用例解密后填入。
struct VideoGenerationOutcome: Hashable, Sendable {
    static let succeededStatus: String = "succeeded"

    let jobID: UUID
    let entryURL: String?
    let status: String
    let finishedAt: String?
    let catalogSourceID: String?
    let reason: String?
    let reasonDetail: String?
    var expiresAt: Date? = nil
    var source: VideoGenerationReusedCatalogSource? = nil
    var catalogSource: CatalogSource? = nil

    /// 中文注释：服务端 `finishedAt`（ISO 8601，常带 6 位小数秒）。解析不了返回 nil——调用方按「不知道何时完成」处理。
    var finishedDate: Date? {
        guard let finishedAt: String = self.finishedAt else {
            return nil
        }
        let fractional: ISO8601DateFormatter = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date: Date = fractional.date(from: finishedAt) {
            return date
        }
        let plain: ISO8601DateFormatter = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let withoutFraction: String = finishedAt.replacingOccurrences(
            of: #"\.\d+"#,
            with: "",
            options: .regularExpression
        )
        return plain.date(from: withoutFraction)
    }

    var didSucceed: Bool {
        return self.status == Self.succeededStatus
    }
}

/// 读取任务终态的客户端稳定错误分类；由 Infrastructure 适配器从 transport 错误映射而来。
enum VideoGenerationOutcomesClientError: Error, Hashable, Sendable {
    case authRequired
    case notFound
    case server(code: String)
    case transport
}

/// 读取 / 删除调用者自己的生成任务终态的 Application 端口。
protocol VideoGenerationOutcomesFetching: Sendable {
    func fetchOutcomes(accessToken: String) async throws -> [VideoGenerationOutcome]
    /// 服务端软删除：对本人隐藏，规则数据保留。
    func hideOutcome(jobID: UUID, accessToken: String) async throws
}
