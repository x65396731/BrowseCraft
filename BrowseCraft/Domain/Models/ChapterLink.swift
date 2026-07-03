import Foundation

// 中文注释：ChapterLink.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：从漫画详情页解析出的标准化章节链接。
/// 中文注释：列表页只给出作品详情地址，阅读器需要先解析到具体章节地址。
struct ChapterLink: Hashable {
    var title: String
    var url: String
}
