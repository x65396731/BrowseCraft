import Foundation

// 中文注释：诊断枚举集中定义 Firebase 字段取值，避免散落字符串造成查询口径不一致。

enum DiagnosticScreen: String {
    case sourceList
    case addSource
    case sourceDetail
    case ruleEditor
    case library
    case favorite
    case history
    case settings
    case comicReader
    case rssList
    case rssDetail
    case videoDetail
    case videoPlayer
}

enum DiagnosticSourceType: String {
    case comic
    case video
    case rss
    case unknown
}

enum DiagnosticRuleStage: String {
    case search
    case list
    case detail
    case chapter
    case reader
    case videoPlayback
    case rssFeed
    case unknown
}

enum DiagnosticSeverity: String {
    case info
    case warning
    case error
    case fatal
}

enum DiagnosticLogCategory: String {
    case network
    case parser
    case database
    case playback
    case sync
    case ui
    case unknown
}
