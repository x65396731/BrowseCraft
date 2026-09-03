import Foundation

// 中文注释：ChapterLink 是详情页到阅读器之间传递的章节入口模型。

public enum ChapterNavigationOrder: Hashable, Sendable {
    case ascending
    case descending
}

/// 中文注释：从漫画详情页解析出的标准化章节链接。
/// 中文注释：列表页只给出作品详情地址，阅读器需要先解析到具体章节地址。
public struct ChapterLink: Hashable, Sendable {
    public init(
        title: String,
        subtitle: String? = nil,
        url: String,
        isRestricted: Bool? = nil,
        isPaid: Bool? = nil,
        navigationChapterURLs: [String] = [],
        navigationChapterTitles: [String?] = [],
        navigationOrder: ChapterNavigationOrder = .descending
    ) {
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.isRestricted = isRestricted
        self.isPaid = isPaid
        self.navigationChapterURLs = navigationChapterURLs
        self.navigationChapterTitles = navigationChapterTitles
        self.navigationOrder = navigationOrder
    }

    public var title: String
    public var subtitle: String? = nil
    public var url: String
    /// 中文注释：nil 表示规则未声明或响应未返回，不能把未知状态猜成可访问。
    public var isRestricted: Bool? = nil
    /// 中文注释：nil 表示付费属性未知；付费章节也可能已购买并可访问。
    public var isPaid: Bool? = nil
    /// 中文注释：详情页进入 Reader 时携带完整章节 URL 顺序，供缺少前后章链接的 reader/API 规则补齐导航。
    public var navigationChapterURLs: [String] = []
    /// 中文注释：与 navigationChapterURLs 按索引对齐；nil 表示历史记录尚未保存该相邻章节标题。
    public var navigationChapterTitles: [String?] = []
    /// 中文注释：章节数组的规则排序方向；未声明时沿用漫画站常见的新章在前顺序。
    public var navigationOrder: ChapterNavigationOrder = .descending
}
