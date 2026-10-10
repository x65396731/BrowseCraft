import Foundation

/// Catalog transport is isolated from APIKit and platform frameworks at compile time.
/// 中文注释：只有 App 消费目录条目，2026-10-10 从 BrowseCraftDomain 搬回（内核只收容 App 与 Runtime 都需要的类型）。
struct CatalogSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let baseURL: String
    let kind: CatalogSourceKind
    let ruleJSON: String

    init(
        id: String,
        name: String,
        baseURL: String,
        kind: CatalogSourceKind,
        ruleJSON: String
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.kind = kind
        self.ruleJSON = ruleJSON
    }
}

enum CatalogSourceKind: String, Codable, Hashable, Sendable {
    case comic
    case video
    /// 中文注释：读书 kind（BC-BOOK-001）；服务器 2026-09-13 起可下发。
    case book
}
