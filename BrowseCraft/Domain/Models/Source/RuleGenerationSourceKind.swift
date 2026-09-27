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

/// 取页档位（`BC-ACQ-071`，设计书第 29 节）：由用户在提交生成时自选，不由任何条件触发。
enum GenerationAcquisitionTier: String, Hashable, Sendable, CaseIterable {
    /// 服务器自己的出口（免费档的行为；服务端价格 `pricing.normal`）。
    case normal
    /// 全部站点请求经 crawl4ai 云端取页（服务端价格 `pricing.hard`；失败也扣）。
    case hard

    /// 发给服务端的字段值：普通档不发（服务端缺省即普通档，也兼容旧服务端）。
    var requestValue: String? {
        return self == .hard ? self.rawValue : nil
    }
}

