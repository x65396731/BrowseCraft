import Foundation

// 中文注释：VideoRenderRequirement 表达取得 HTML 的要求；它不是内容 mapper 类型。
enum VideoRenderRequirement: String, Codable, Hashable {
    case staticHTML
    case webViewRequired
}
