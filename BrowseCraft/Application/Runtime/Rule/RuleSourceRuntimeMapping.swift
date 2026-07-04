import Foundation
import BrowseCraftCore

// 中文注释：RuleSourceRuntimeAdapter 的本地映射层；只翻译 App 模型和 Core runtime 合同，不作为独立架构边界。
struct SourceDefinitionMapper {
    func definition(from source: Source) -> SourceDefinition {
        return SourceDefinition(
            id: source.id,
            kind: .rule,
            name: source.name,
            baseURL: self.baseURL(from: source.baseURL),
            version: source.rule.version,
            ownership: self.ownership(for: source),
            rule: RuleSourceDefinition(
                ruleID: source.id,
                schemaVersion: source.rule.version ?? 1,
                packageMetadata: nil,
                isEditable: source.isBuiltIn == false
            ),
            rss: nil,
            plugin: nil
        )
    }

    private func baseURL(from string: String) -> URL {
        let normalizedString: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedString.isEmpty == false,
           let url: URL = URL(string: normalizedString) {
            return url
        }

        return URL(string: "about:blank")!
    }

    private func ownership(for source: Source) -> SourceOwnership {
        if source.isBuiltIn {
            return .builtIn
        }

        return .user
    }
}

struct SourceRuntimeOutputMapper {
    func contentItem(from item: ContentItem) -> SourceContentItem {
        return SourceContentItem(
            id: item.id,
            title: item.title,
            detailURL: self.url(from: item.detailURL),
            coverURL: self.url(from: item.coverURL),
            latestText: item.latestText
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
                url: url
            )
        }
    }

    func readerChapter(from chapter: ReaderChapter) -> SourceReaderChapter {
        return SourceReaderChapter(
            title: chapter.chapterTitle,
            imageURLs: chapter.pageImageURLs.compactMap { imageURL in
                return self.url(from: imageURL)
            }
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
        chapters: [ChapterLink],
        diagnostics: SourceRuntimeDiagnostics
    ) -> SourceDetailOutput {
        return SourceDetailOutput(
            chapters: self.chapters(from: chapters),
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
}
