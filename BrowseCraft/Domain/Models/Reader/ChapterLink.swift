import Foundation

// 中文注释：ChapterLink 是详情页到阅读器之间传递的章节入口模型。

/// 中文注释：从漫画详情页解析出的标准化章节链接。
/// 中文注释：列表页只给出作品详情地址，阅读器需要先解析到具体章节地址。
struct ChapterLink: Hashable {
    var title: String
    var subtitle: String? = nil
    var url: String
}
