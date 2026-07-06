import Foundation

// 中文注释：VideoEpisode 是 video runtime 内部剧集模型，避免把漫画章节语义扩散到视频 UI。
struct VideoEpisode: Identifiable, Hashable {
    var id: String
    var title: String
    var playPageURL: URL
}

// 中文注释：VideoDetailContent 是 video detail loader 的内部映射结果，UI 只读取必要字段。
struct VideoDetailContent {
    var episodes: [VideoEpisode]
    var synopsis: String?
    var metadataRows: [String]
}
