import Foundation

// 中文注释：临时漫画发现结果只用于当前页面展示，不会写入 Source DB。
struct TransientComicDiscoveryItem: Identifiable, Hashable {
    var id: String
    var title: String
    var detailURL: String
    var coverURL: String?
    var latestText: String?
    var matchedKeyword: String
    var sourcePageURL: String
}
