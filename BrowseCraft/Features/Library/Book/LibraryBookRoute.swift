import BrowseCraftDomain
import Foundation

// 中文注释：本地书与站点书在 Library 导航栈里的路由。只在 LibraryView 的栈根声明一次
// navigationDestination——SwiftUI 只认离根最近的那个声明，子视图里再声明第二级会被忽略（2026-09-14 模拟器实测）。

enum LibraryBookRoute: Hashable {
    /// 中文注释：本地书架（入口已藏，路由保留）。
    case shelf
    /// 中文注释：本地书阅读器。
    case book(LocalBook)
    // 中文注释：站点书的章节不走这里——详情页是 item 式推入的，章节也用详情页自己的 item 式推入
    // （BookSiteDetailView），value 式与 item 式混用会打乱栈序（2026-09-14 模拟器实测）。
}

/// 中文注释：Library 列表点开一部站点书时的目的地（与 LibraryComicDestination 同形）。
struct LibrarySiteBookDestination: Identifiable, Hashable {
    let item: ContentItem
    let source: Source

    var id: String {
        return [self.source.id, self.item.id, self.item.detailURL].joined(separator: "|")
    }
}
