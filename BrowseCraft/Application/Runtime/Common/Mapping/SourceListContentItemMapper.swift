import BrowseCraftCore
import Foundation

struct SourceListContentItemMapper {
    func map(
        output: SourceListOutput,
        source: Source,
        context: ListContext?
    ) -> [ContentItem] {
        return output.items.enumerated().map { index, item in
            ContentItem(
                id: item.id,
                idCode: item.idCode,
                sourceId: source.id,
                title: item.title,
                detailURL: item.detailURL?.absoluteString ?? item.id,
                coverURL: item.coverURL?.absoluteString,
                type: self.contentType(for: source),
                latestText: item.latestText,
                richContent: item.richContent,
                updatedAt: item.updatedAt,
                listOrder: index,
                listContext: context
            )
        }
    }

    private func contentType(for source: Source) -> SourceContentKind {
        switch source.configuration {
        case .rss, .plugin:
            return .article
        case .comic:
            return .comic
        case .video:
            return .video
        }
    }
}
