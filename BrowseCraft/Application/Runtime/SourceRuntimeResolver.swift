import Foundation
import BrowseCraftCore

protocol SourceRuntimeResolving {
    func runtime(for source: Source) throws -> any SourceRuntime
}

struct SourceRuntimeResolver: SourceRuntimeResolving {
    private let ruleRuntimeFactory: (Source) -> any SourceRuntime

    init(ruleRuntimeFactory: @escaping (Source) -> any SourceRuntime) {
        self.ruleRuntimeFactory = ruleRuntimeFactory
    }

    func runtime(for source: Source) throws -> any SourceRuntime {
        switch source.type {
        case .html, .json, .xml:
            // 中文注释：这些旧 SourceType 目前仍映射到 rule-backed runtime；
            // 后续 RSS/Plugin 应注册独立 runtime，而不是塞进 SiteRule JSON。
            return self.ruleRuntimeFactory(source)
        case .rss:
            throw SourceRuntimeError.unsupported(
                .custom("RSS source runtime is reserved for P3-8 and is not connected yet.")
            )
        }
    }
}
