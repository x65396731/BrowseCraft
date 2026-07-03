import Foundation
import BrowseCraftCore

// 中文注释：SourceRuntimeOutputBridge 把 App 现有解析结果转换成 Core runtime 输出，不持有网络、数据库或 UI 状态。
struct SourceRuntimeOutputBridge {
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

    func diagnostics(status: SourceRuntimeStatus, issues: [SourceRuntimeIssue] = []) -> SourceRuntimeDiagnostics {
        return SourceRuntimeDiagnostics(
            status: status,
            requestLogs: [],
            extractionLogs: [],
            issues: issues
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
