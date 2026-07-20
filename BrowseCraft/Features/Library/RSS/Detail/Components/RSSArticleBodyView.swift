import SwiftUI

struct RSSArticleBodyView: View {
    let item: ContentItem
    let originalURL: URL?

    @ViewBuilder
    var body: some View {
        if let payload: RSSContentPayload = self.item.richContent
            ?? RSSContentPayload.decode(from: self.item.latestText),
           payload.blocks.isEmpty == false {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(payload.blocks.filter { block in block.kind != .image }.enumerated()), id: \.element.id) { index, block in
                    self.articleBlock(block)
                        .padding(.top, self.articleBlockTopPadding(block: block, index: index))
                }
            }
        } else if let summary: String = RSSContentTextFormatter.sanitized(self.item.latestText) {
            self.paragraphText(summary)
        }
    }

    @ViewBuilder
    private func articleBlock(_ block: RSSContentPayload.Block) -> some View {
        switch block.kind {
        case .subtitle:
            if let text: String = block.text {
                Text(text)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(RSSContentDetailStyle.primaryTextColor)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph:
            if let text: String = block.text {
                self.paragraphText(text)
            }
        case .image:
            if let imageURL: String = block.imageURL {
                CoverImageView(urlString: self.displayImageURLString(from: imageURL))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 190)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.vertical, 2)
            }
        }
    }

    private func articleBlockTopPadding(block: RSSContentPayload.Block, index: Int) -> CGFloat {
        guard index > 0 else {
            return 0
        }

        switch block.kind {
        case .subtitle:
            return 34
        case .paragraph:
            return 16
        case .image:
            return 20
        }
    }

    private func paragraphText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(RSSContentDetailStyle.primaryTextColor)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }


    private func displayImageURLString(from urlString: String) -> String {
        guard let url: URL = URL(string: urlString, relativeTo: self.originalURL)?.absoluteURL else {
            return urlString
        }

        return url.absoluteString
    }
}
