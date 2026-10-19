import Foundation

/// Catalog transport is isolated from APIKit and platform frameworks at compile time.
/// 中文注释：只有 App 消费目录条目，2026-10-10 从 BrowseCraftDomain 搬回（内核只收容 App 与 Runtime 都需要的类型）。
struct CatalogSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let baseURL: String
    let kind: CatalogSourceKind
    let ruleJSON: String
    /// 公共目录分区；个人规则、没带 `section` 或取值不认得的条目为 nil，「发现」里不展示（合同 2.2）。
    let section: CatalogSourceSection?
    /// 服务端规则指纹（PortalCore `catalogSHA256`，明文下发）；应用规则时记到来源行上，问题报告随报文带回（`BCA-OBS-022`）。
    /// 旧服务端不带时为 nil。
    let catalogRevision: String?

    init(
        id: String,
        name: String,
        baseURL: String,
        kind: CatalogSourceKind,
        ruleJSON: String,
        section: CatalogSourceSection? = nil,
        catalogRevision: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.kind = kind
        self.ruleJSON = ruleJSON
        self.section = section
        self.catalogRevision = catalogRevision
    }
}

/// 公共目录分区（PortalCore `section`，`docs/design/Catalog-Page-Redesign-Design.md` 2.2）。
/// `internal` 只返回给白名单账号，App 只在 Debug 构建展示；`shared` 是用户分享的占位，本版不展示。
enum CatalogSourceSection: String, Hashable, Sendable {
    case example
    case internalTest = "internal"
    case shared
}

enum CatalogSourceKind: String, Codable, Hashable, Sendable {
    case comic
    case video
    /// 中文注释：读书 kind（BC-BOOK-001）；服务器 2026-09-13 起可下发。
    case book
}
