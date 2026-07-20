import SwiftUI

struct RSSArticleMetadataPanel: View {
    let metadata: RSSContentPayload.Metadata?

    @ViewBuilder
    var body: some View {
        if let metadata: RSSContentPayload.Metadata = self.metadata {
            VStack(spacing: 28) {
                if metadata.tags.isEmpty == false {
                    HStack(spacing: 22) {
                        ForEach(metadata.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(RSSContentDetailStyle.primaryTextColor.opacity(0.72))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(RSSContentDetailStyle.metadataBackgroundColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 32) {
                    if let likeCount: Int = metadata.likeCount {
                        self.metricChip(systemImage: "hand.thumbsup.fill", value: likeCount)
                    }

                    self.metricChip(systemImage: "text.bubble.fill", value: metadata.commentCount ?? 0)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricChip(systemImage: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))

            Text("\(value)")
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
        }
        .foregroundColor(RSSContentDetailStyle.metricTextColor)
        .padding(.horizontal, 24)
        .frame(height: 48)
        .background(RSSContentDetailStyle.metadataBackgroundColor)
        .clipShape(Capsule())
    }
}
