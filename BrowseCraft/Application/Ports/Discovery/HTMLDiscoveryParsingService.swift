import Foundation

struct HTMLDiscoveryAncestorSnapshot: Hashable {
    let text: String
    let className: String
    let id: String
}

struct HTMLDiscoveryAnchorSnapshot: Hashable {
    let text: String
    let href: String
    let title: String
    let imageAlt: String
    let className: String
    let id: String
    let hasImage: Bool
    /// 中文注释：从直接 parent 开始，按向外层级排列，数量由解析 adapter 限制。
    let ancestors: [HTMLDiscoveryAncestorSnapshot]
    /// 中文注释：按 anchor → ancestors 的既有优先级排列，每层只保留当前选择器命中的首个候选。
    let coverURLCandidates: [String]
}

/// 中文注释：仅把 HTML 转成 Discovery 用快照，不向 Application 暴露 DOM 查询能力。
protocol HTMLDiscoveryParsingService {
    func parseAnchors(html: String, pageURL: URL) throws -> [HTMLDiscoveryAnchorSnapshot]
}
