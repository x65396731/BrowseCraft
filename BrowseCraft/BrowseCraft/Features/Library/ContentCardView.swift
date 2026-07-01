import SwiftUI

// 中文注释：ContentCardView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：ContentCardView 是 struct，负责本模块中的对应职责。
struct ContentCardView<ReaderDestination: View>: View {
    let item: ContentItem
    let sourceName: String
    let isFavorite: Bool
    let favoriteAction: () -> Void
    let readAction: () -> Void
    let readerDestination: ReaderDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                CoverImageView(
                    urlString: self.item.coverURL,
                    refererURLString: self.item.detailURL
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
                            Text("Chapters")
                        },
                        icon: {
                            Image(systemName: "list.bullet")
                        }
                    )
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
            )
            .simultaneousGesture(
                TapGesture().onEnded {
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
