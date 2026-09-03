import Foundation

// 中文注释：VideoRenderRequirement 表达取得 HTML 的要求；它不是内容 mapper 类型。
public enum VideoRenderRequirement: String, Codable, Hashable, Sendable {
    case staticHTML
    case webViewRequired
}
