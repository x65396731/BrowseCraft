import Foundation
import BrowseCraftCore

// 中文注释：详情入口只依赖 SourceRuntime；具体漫画规则加载器由 runtime 内部装配。
struct LoadChaptersUseCase {
    private let runtimeResolver: any SourceRuntimeResolving
    private let itemReferenceMapper: SourceItemReferenceMapper = SourceItemReferenceMapper()

    init(runtimeResolver: any SourceRuntimeResolving) {
        self.runtimeResolver = runtimeResolver
    }

    func execute(source: Source, item: ContentItem) async throws -> SourceDetailOutput {
        guard let detailURL: URL = URL(string: item.detailURL) else {
            throw SourceRuntimeError.invalidInput("Invalid detail URL: \(item.detailURL)")
        }

        let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: source)
        return try await runtime.loadDetail(
            SourceDetailInput(
                detailURL: detailURL,
                context: SourceRuntimeContext(
                    sourceID: source.id,
                    pageID: item.listContext?.pageId,
                    tabID: item.listContext?.tabId,
                    sectionID: item.listContext?.sectionId,
                    sectionRole: item.listContext?.sectionRole?.rawValue,
                    ruleID: item.listContext?.listRuleId,
                    requestOverride: nil,
                    debugMode: false,
                    operation: .detail
                ),
                itemReference: self.itemReferenceMapper.reference(from: item, intent: .detail)
            )
        )
    }
}

// 中文注释：Reader 入口同样只依赖 SourceRuntime；App 模型是界面投影，不再是加载合同。
struct LoadReaderChapterUseCase {
    private let runtimeResolver: any SourceRuntimeResolving
    private let itemReferenceMapper: SourceItemReferenceMapper = SourceItemReferenceMapper()

    init(runtimeResolver: any SourceRuntimeResolving) {
        self.runtimeResolver = runtimeResolver
    }

    func execute(
        source: Source,
        item: ContentItem,
        chapterURLString: String? = nil
    ) async throws -> ReaderChapter {
        let resolvedURLString: String = chapterURLString ?? item.detailURL
        guard let chapterURL: URL = URL(string: resolvedURLString) else {
            throw SourceRuntimeError.invalidInput("Invalid chapter URL: \(resolvedURLString)")
        }

        let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: source)
        let output: SourceReaderOutput = try await runtime.loadReader(
            SourceReaderInput(
                chapterURL: chapterURL,
                context: SourceRuntimeContext(
                    sourceID: source.id,
                    pageID: item.listContext?.pageId,
                    tabID: item.listContext?.tabId,
                    sectionID: item.listContext?.sectionId,
                    sectionRole: item.listContext?.sectionRole?.rawValue,
                    ruleID: item.listContext?.listRuleId,
                    requestOverride: nil,
                    debugMode: false,
                    operation: .reader
                ),
                itemReference: self.itemReferenceMapper.reference(
                    from: item,
                    chapterURL: chapterURL,
                    intent: .directReader
                )
            )
        )
        return self.readerChapter(from: output.chapter)
    }

    private func readerChapter(from chapter: SourceReaderChapter) -> ReaderChapter {
        return ReaderChapter(
            sourceId: chapter.sourceID,
            comicTitle: chapter.comicTitle,
            chapterTitle: chapter.chapterTitle,
            chapterURL: chapter.chapterURL.absoluteString,
            catalogURL: chapter.catalogURL?.absoluteString,
            previousChapterURL: chapter.previousChapterURL?.absoluteString,
            nextChapterURL: chapter.nextChapterURL?.absoluteString,
            pageImageURLs: chapter.imageURLs.map(\.absoluteString),
            pageResources: chapter.pageResources.map { self.readerPageResource(from: $0) },
            pageImageHeaders: Dictionary(
                uniqueKeysWithValues: chapter.imageHeaders.map { key, value in
                    return (key.absoluteString, value)
                }
            )
        )
    }

    private func readerPageResource(from resource: SourceReaderPageResource) -> ReaderPageResource {
        switch resource {
        case .remoteImageURL(let url):
            return .remoteImageURL(url.absoluteString)
        case .protectedResource(let reference):
            return .protectedResource(self.protectedReference(from: reference))
        }
    }

    private func protectedReference(
        from reference: SourceProtectedReaderImageReference
    ) -> ProtectedReaderImageReference {
        let displayURLString: String = reference.displayURL?.absoluteString ?? "about:blank"
        let execution: ProtectedReaderImageExecution
        switch reference.execution {
        case .legacy(let legacy):
            execution = .legacy(
                self.legacyReference(
                    from: legacy,
                    displayURLString: displayURLString,
                    sourceID: reference.sourceID,
                    baseURL: reference.baseURL
                )
            )
        case .pipeline(let pipeline):
            execution = .pipeline(
                ResourcePipelineReaderImageReference(
                    displayURLString: displayURLString,
                    sourceID: reference.sourceID,
                    baseURL: reference.baseURL,
                    rule: pipeline.rule,
                    item: pipeline.item.mapValues { self.readerValue(from: $0) },
                    root: pipeline.root.mapValues { self.readerValue(from: $0) },
                    context: pipeline.context.mapValues { self.readerValue(from: $0) },
                    legacyFallback: pipeline.legacyFallback.map { legacy in
                        return self.legacyReference(
                            from: legacy,
                            displayURLString: displayURLString,
                            sourceID: reference.sourceID,
                            baseURL: reference.baseURL
                        )
                    }
                )
            )
        }

        return ProtectedReaderImageReference(execution: execution)
    }

    private func legacyReference(
        from reference: SourceLegacyProtectedReaderImageReference,
        displayURLString: String,
        sourceID: String,
        baseURL: URL?
    ) -> LegacyProtectedReaderImageReference {
        return LegacyProtectedReaderImageReference(
            displayURLString: displayURLString,
            sourceID: sourceID,
            baseURL: baseURL,
            rule: reference.rule,
            parameters: reference.parameters
        )
    }

    private func readerValue(from value: SourceRuntimeValue) -> ReaderResourcePipelineValue {
        switch value {
        case .string(let value): return .string(value)
        case .number(let value): return .number(value)
        case .boolean(let value): return .boolean(value)
        case .object(let value): return .object(value.mapValues { self.readerValue(from: $0) })
        case .array(let value): return .array(value.map { self.readerValue(from: $0) })
        case .null: return .null
        }
    }
}
