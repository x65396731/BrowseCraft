import SwiftUI

struct ContentCardView: View {
    let item: ContentItem
    let sourceName: String
    let isFavorite: Bool
    let favoriteAction: () -> Void
    let openAction: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                CoverImageView(urlString: self.item.coverURL)
                    .aspectRatio(0.72, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(
                    action: {
                        self.favoriteAction()
                    },
                    label: {
                        Image(systemName: self.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(self.isFavorite ? .yellow : .white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.45))
                            )
                    }
                )
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel(self.isFavorite ? "Remove Favorite" : "Add Favorite")
            }

            Text(self.item.title)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Label(
                    title: {
                        Text(self.item.type.rawValue.capitalized)
                    },
                    icon: {
                        Image(systemName: self.iconName(for: self.item.type))
                    }
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

                Spacer(minLength: 6)

                Text(self.sourceName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if let latestText: String = self.item.latestText {
                Text(latestText)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }

            Button(
                action: {
                    self.openAction()

                    if let url: URL = URL(string: self.item.detailURL) {
                        self.openURL(url)
                    }
                },
                label: {
                    Label(
                        title: {
                            Text("Open")
                        },
                        icon: {
                            Image(systemName: "safari")
                        }
                    )
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
            )
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private func iconName(for contentType: ContentType) -> String {
        switch contentType {
        case .comic:
            return "photo.on.rectangle"
        case .video:
            return "play.rectangle"
        case .article:
            return "doc.text"
        case .gallery:
            return "photo.stack"
        }
    }
}
