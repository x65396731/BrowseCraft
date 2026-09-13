import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation

// 中文注释：LoadBookPublicationUseCase：站点书的作品页 → Runtime 详情 → manifest，并把 Runtime 的 loadBookContent 包成按需取内容的 provider。

struct LoadedBookPublication: Sendable {
    let manifest: BookPublicationManifest
    let contentProvider: BookChapterContentProvider
}

enum LoadBookPublicationError: Error, Equatable, Sendable {
    case runtimeIsNotBookCapable(sourceID: String)
}

struct LoadBookPublicationUseCase: Sendable {
    private let runtimeResolver: any SourceRuntimeResolving
    private let assembler: BookPublicationAssembler

    init(runtimeResolver: any SourceRuntimeResolving, assembler: BookPublicationAssembler = BookPublicationAssembler()) {
        self.runtimeResolver = runtimeResolver
        self.assembler = assembler
    }

    func execute(source: Source, detailURL: URL) async throws -> LoadedBookPublication {
        let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: source)
        guard let detailRuntime: any SourceDetailRuntime = runtime as? any SourceDetailRuntime,
              let contentRuntime: any SourceBookContentRuntime = runtime as? any SourceBookContentRuntime else {
            throw LoadBookPublicationError.runtimeIsNotBookCapable(sourceID: source.id)
        }
        let context: SourceRuntimeContext = SourceRuntimeContext(
            sourceID: source.id,
            pageID: nil,
            tabID: nil,
            ruleID: nil,
            requestOverride: nil,
            debugMode: false
        )
        let detail: SourceDetailOutput = try await detailRuntime.loadDetail(SourceDetailInput(detailURL: detailURL, context: context, itemReference: nil))
        let manifest: BookPublicationManifest = self.assembler.assemble(source: source, detailURL: detailURL, detail: detail)
        let provider: BookChapterContentProvider = { chapterURL in
            return try await contentRuntime.loadBookContent(SourceBookContentInput(chapterURL: chapterURL, context: context)).content
        }
        return LoadedBookPublication(manifest: manifest, contentProvider: provider)
    }
}
