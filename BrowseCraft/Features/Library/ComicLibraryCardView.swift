import SwiftUI

// 中文注释：ComicLibraryCardView.swift 属于 Library 漫画展示层，用于展示漫画封面和章节入口。

/// 中文注释：ComicLibraryCardView 是漫画源在 Library 中使用的封面卡片。
struct ComicLibraryCardView<ReaderDestination: View>: View {
    let item: ContentItem
    let sourceName: String
    let primaryActionTitle: String
    let primaryActionSystemImage: String
    let isFavorite: Bool
    let favoriteAction: () -> Void
    let readAction: () -> Void
    let readerDestination: ReaderDestination
    let imageRequestConfig: RequestConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ItemThumbnailImageView(
                    urlString: self.item.coverURL,
                    refererURLString: self.item.detailURL,
                    requestConfig: self.imageRequestConfig
                )
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

            NavigationLink(
                destination: self.readerDestination,
                label: {
                    Label(
                        title: {
                            Text(self.primaryActionTitle)
                        },
                        icon: {
                            Image(systemName: self.primaryActionSystemImage)
                        }
                    )
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
            )
            .simultaneousGesture(
                TapGesture().onEnded {
                    #if DEBUG
                    print(
                        "[BrowseCraftNavigation] Tap \(self.primaryActionTitle) " +
                        "itemId=\(self.item.id) " +
                        "title=\(self.item.title) " +
                        "detailURL=\(self.item.detailURL) " +
                        "latestText=\(self.item.latestText ?? "nil")"
                    )
                    #endif

                    self.readAction()
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

    /// 中文注释：iconName 方法封装当前类型的一段业务或界面行为。
    private func iconName(for contentType: SourceContentKind) -> String {
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
