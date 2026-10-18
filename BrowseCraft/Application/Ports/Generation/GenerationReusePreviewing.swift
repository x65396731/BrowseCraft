import Foundation

/// 这个网址此刻提交会直接取用现成规则（docs/design/Generation-Input-Page-Redesign-Design.md 第三、六节）。
///
/// 中文注释：`coinCost` 是取用要扣的 coin，本人 7 天内生成的为 0。不可取用时端口返回 nil，不构造这个值。
struct GenerationReusePreview: Hashable, Sendable {
    let coinCost: Int
}

/// 提交前只读预览能不能直接取用现成规则的 Application 端口（PortalCore `GET /v1/rule-generations/reuse-preview`）。
///
/// 中文注释：与提交走同一个服务端复用判定，所以 `entryURL` 与 `sourceKind` 必须与随后提交时的一致；
/// 实现方负责带上与提交相同的地区。只读：不下发规则、不扣费、不排队。
protocol GenerationReusePreviewing: Sendable {
    func reusePreview(
        sourceKind: RuleGenerationSourceKind,
        entryURL: String,
        accessToken: String
    ) async throws -> GenerationReusePreview?
}
