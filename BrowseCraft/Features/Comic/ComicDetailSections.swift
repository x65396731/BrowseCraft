import SwiftUI

struct ComicDetailHeroSection: View {
    let title: String
    let author: String?
    let status: String?
    let category: String?
    let sourceName: String
    let coverURLString: String?
    let detailURLString: String
    let requestConfig: RequestConfig?

    var body: some View {
        ZStack(alignment: .bottom) {
            CoverImageView(
                urlString: self.coverURLString,
                refererURLString: self.detailURLString,
                requestConfig: self.requestConfig
            )
            .frame(maxWidth: .infinity)
            .frame(height: 330)
            .blur(radius: 18)
            .scaleEffect(1.12)
            .overlay(Color.black.opacity(0.34))

            LinearGradient(
                colors: [.clear, Color(.systemGroupedBackground).opacity(0.34), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 18) {
                CoverImageView(
                    urlString: self.coverURLString,
                    refererURLString: self.detailURLString,
                    requestConfig: self.requestConfig
                )
                .frame(width: 118, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.24), radius: 14, y: 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(self.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    Text(self.author ?? self.sourceName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let status: String = self.status {
                            ComicDetailBadge(text: status, tint: .indigo)
                        }
                        if let category: String = self.category {
                            ComicDetailBadge(text: category, tint: .gray)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(height: 350)
        .clipped()
    }
}

struct ComicDetailBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(self.text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(self.tint)
            .background(self.tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct ComicDetailActionSection: View {
    let chapterCount: Int
    let latestText: String?
    let readingTitle: String
    let isEnabled: Bool
    let startReading: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: self.startReading) {
                Label(self.readingTitle, systemImage: "book.pages.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.isEnabled == false)

            HStack(spacing: 18) {
                Label("\(self.chapterCount) Chapters", systemImage: "list.bullet.rectangle")
                if let latestText: String = self.latestText {
                    Label(latestText, systemImage: "sparkles")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

struct ComicDetailTagsSection: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(self.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }
}

struct ComicDetailDescriptionSection: View {
    let description: String

    var body: some View {
        ComicDetailCard(title: "About", systemImage: "text.alignleft") {
            Text(self.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ComicDetailInformationSection: View {
    let rows: [ComicDetailMetadataRow]
    let links: [ComicDetailRelatedLink]

    var body: some View {
        ComicDetailCard(title: "Information", systemImage: "info.circle") {
            VStack(spacing: 0) {
                ForEach(Array(self.rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top, spacing: 16) {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .frame(width: 82, alignment: .leading)

                        Text(row.value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 9)

                    if index < self.rows.count - 1 || self.links.isEmpty == false {
                        Divider()
                    }
                }

                ForEach(self.links) { link in
                    Link(destination: link.url) {
                        HStack {
                            Text(link.title)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }
}


struct ComicDetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(self.title, systemImage: self.systemImage)
                .font(.headline)

            self.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
