import Foundation
import BrowseCraftCore

struct ComicRuleSourceRuntimeMapper {
    func contentItem(from item: ContentItem) -> SourceContentItem {
        return SourceContentItem(
            id: item.id,
            title: item.title,
            detailURL: self.url(from: item.detailURL),
            coverURL: self.url(from: item.coverURL),
            latestText: item.latestText,
            updatedAt: item.updatedAt,
            richContent: item.richContent
        )
    }

    func contentItems(from items: [ContentItem]) -> [SourceContentItem] {
        return items.map { item in
            return self.contentItem(from: item)
        }
    }

    func chapters(from chapters: [ChapterLink]) -> [SourceChapter] {
        return chapters.compactMap { chapter in
            guard let url: URL = self.url(from: chapter.url) else {
                return nil
            }

            return SourceChapter(
                id: chapter.url,
                title: chapter.title,
                subtitle: chapter.subtitle,
                url: url,
                navigationChapterURLs: chapter.navigationChapterURLs.compactMap { self.url(from: $0) },
                navigationChapterTitles: chapter.navigationChapterTitles,
                navigationOrder: chapter.navigationOrder == .ascending ? .ascending : .descending
            )
        }
    }

    func readerChapter(from chapter: ReaderChapter) -> SourceReaderChapter {
        let chapterURL: URL = self.url(from: chapter.chapterURL)
            ?? URL(string: "about:blank")!
        return SourceReaderChapter(
            sourceID: chapter.sourceId,
            comicTitle: chapter.comicTitle,
            chapterTitle: chapter.chapterTitle,
            chapterURL: chapterURL,
            catalogURL: self.url(from: chapter.catalogURL),
            previousChapterURL: self.url(from: chapter.previousChapterURL),
            nextChapterURL: self.url(from: chapter.nextChapterURL),
            imageURLs: chapter.pageImageURLs.compactMap { imageURL in
                return self.url(from: imageURL)
            },
            pageResources: chapter.pageResources.compactMap { self.readerPageResource(from: $0) },
            imageHeaders: Dictionary(
                uniqueKeysWithValues: chapter.pageImageHeaders.compactMap { key, value in
                    return self.url(from: key).map { ($0, value) }
                }
            )
        )
    }

    func listOutput(
        items: [ContentItem],
        pagination: SourcePagination? = nil,
        diagnostics: SourceRuntimeDiagnostics
    ) -> SourceListOutput {
        return SourceListOutput(
            items: self.contentItems(from: items),
            pagination: pagination,
            diagnostics: diagnostics
        )
    }

    func detailOutput(
        detail: ComicRuleParsedDetail,
        diagnostics: SourceRuntimeDiagnostics
    ) -> SourceDetailOutput {
        let metadata: ComicRuleParsedDetailMetadata = detail.metadata
        return SourceDetailOutput(
            metadata: SourceDetailMetadata(
                idCode: metadata.idCode,
                title: metadata.title,
                coverURL: self.url(from: metadata.coverURL),
                description: metadata.description,
                author: metadata.author,
                status: metadata.status,
                category: metadata.category,
                tags: metadata.tags,
                language: metadata.language,
                publishedAt: metadata.publishedAt,
                updatedAt: metadata.updatedAt,
                license: metadata.license,
                totalImages: metadata.totalImages,
                photoAlbumURL: self.url(from: metadata.photoAlbumURL),
                secondLevelPageURL: self.url(from: metadata.secondLevelPageURL)
            ),
            chapters: self.chapters(from: detail.chapters),
            diagnostics: diagnostics
        )
    }

    func readerOutput(
        chapter: ReaderChapter,
        diagnostics: SourceRuntimeDiagnostics
    ) -> SourceReaderOutput {
        return SourceReaderOutput(
            chapter: self.readerChapter(from: chapter),
            diagnostics: diagnostics
        )
    }

    private func url(from string: String?) -> URL? {
        guard let string: String = string,
              string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        return URL(string: string)
    }

    private func readerPageResource(from resource: ReaderPageResource) -> SourceReaderPageResource? {
        switch resource {
        case .remoteImageURL(let urlString):
            return self.url(from: urlString).map(SourceReaderPageResource.remoteImageURL)
        case .protectedResource(let reference):
            return .protectedResource(self.protectedReference(from: reference))
        }
    }

    private func protectedReference(
        from reference: ProtectedReaderImageReference
    ) -> SourceProtectedReaderImageReference {
        let execution: SourceProtectedReaderImageExecution
        switch reference.execution {
        case .legacy(let legacy):
            execution = .legacy(self.legacyReference(from: legacy))
        case .pipeline(let pipeline):
            execution = .pipeline(
                SourceResourcePipelineReaderImageReference(
                    rule: pipeline.rule,
                    item: pipeline.item.mapValues { self.runtimeValue(from: $0) },
                    root: pipeline.root.mapValues { self.runtimeValue(from: $0) },
                    context: pipeline.context.mapValues { self.runtimeValue(from: $0) },
                    legacyFallback: pipeline.legacyFallback.map { self.legacyReference(from: $0) }
                )
            )
        }

        return SourceProtectedReaderImageReference(
            displayURL: self.url(from: reference.displayURLString),
            sourceID: reference.sourceID,
            baseURL: reference.baseURL,
            execution: execution
        )
    }

    private func legacyReference(
        from reference: LegacyProtectedReaderImageReference
    ) -> SourceLegacyProtectedReaderImageReference {
        return SourceLegacyProtectedReaderImageReference(
            rule: reference.rule,
            parameters: reference.parameters
        )
    }

    private func runtimeValue(from value: ReaderResourcePipelineValue) -> SourceRuntimeValue {
        switch value {
        case .string(let value): return .string(value)
        case .number(let value): return .number(value)
        case .boolean(let value): return .boolean(value)
        case .object(let value): return .object(value.mapValues { self.runtimeValue(from: $0) })
        case .array(let value): return .array(value.map { self.runtimeValue(from: $0) })
        case .null: return .null
        }
    }
}
