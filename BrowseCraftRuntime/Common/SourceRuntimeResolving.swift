import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：UseCase 只依赖 runtime 解析协议；具体分发和装配由 SourceRuntimeFactory 负责。
public protocol SourceRuntimeResolving: Sendable {
    func runtime(for source: Source) throws -> any SourceRuntime
}
