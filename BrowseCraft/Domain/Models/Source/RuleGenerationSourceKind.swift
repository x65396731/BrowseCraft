import Foundation

/// 服务端规则生成支持的来源类型（PortalCore `POST /v1/rule-generations` 的 `sourceKind`）。
///
/// 中文注释：服务端 schema 是 `Literal["video", "comic", "book"]`（PortalCore 2026-09-13 起）；`rss` 已随生成侧下线。
/// 刻意不复用 `CatalogSourceKind`：那是「目录里能有哪几种来源」，与「能生成哪几种」不是同一件事。
enum RuleGenerationSourceKind: String, Hashable, Sendable, CaseIterable {
    case video
    case comic
    case book
}
