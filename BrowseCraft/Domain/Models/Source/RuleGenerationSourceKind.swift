import Foundation

/// 服务端规则生成支持的来源类型（PortalCore `POST /v1/rule-generations` 的 `sourceKind`）。
///
/// 中文注释：服务端 schema 是 `Literal["video", "comic"]`——`SourceKind` 里还有 `rss`，
/// 但它不在分层生成链上，提交会被 400 拒收，因此这里同样不表达它。刻意不复用
/// `CatalogSourceKind`：那是「目录里能有哪几种来源」，与「能生成哪几种」不是同一件事。
enum RuleGenerationSourceKind: String, Hashable, Sendable, CaseIterable {
    case video
    case comic
}
