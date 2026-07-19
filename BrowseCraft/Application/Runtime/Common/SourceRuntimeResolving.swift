import Foundation
import BrowseCraftCore

// 中文注释：UseCase 只依赖 runtime 解析协议；具体分发和装配由 SourceRuntimeFactory 负责。
protocol SourceRuntimeResolving {
    func runtime(for source: Source) throws -> any SourceRuntime
}
