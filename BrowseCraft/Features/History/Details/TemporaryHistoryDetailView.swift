import SwiftUI

struct TemporaryHistoryDetailView: View {
    let history: TemporaryResourceHistory

    var body: some View {
        Form {
            Section("Resource") {
                if let coverURL: URL = self.history.coverURL {
                    ItemThumbnailImageView(
                        urlString: coverURL.absoluteString,
                        refererURLString: self.history.resourceURL.absoluteString,
                        requestConfig: nil
                    )
                    .aspectRatio(self.history.kind == .video ? 1.45 : 0.72, contentMode: .fit)
                    .frame(maxWidth: self.history.kind == .video ? 220 : 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text(self.history.title)
                    .font(.title3.weight(.semibold))

                LabeledContent("Type", value: self.history.kind == .video ? "Temporary Video" : "Temporary Comic")
                LabeledContent("Visited", value: Self.dateFormatter.string(from: self.history.visitedAt))
            }

            Section("Open") {
                if self.history.kind == .video {
                    NavigationLink {
                        TemporaryHistoryWebPlayerScreen(
                            url: self.history.resourceURL,
                            title: self.history.title
                        )
                    } label: {
                        Label("Open in Web Player", systemImage: "safari")
                    }

                    if self.history.videoPlaybackKind == .directMedia {
                        NavigationLink {
                            TemporaryHistoryNativePlayerScreen(
                                mediaURL: self.history.resourceURL,
                                title: self.history.title
                            )
                        } label: {
                            Label("Open in Native Player", systemImage: "play.circle")
                        }
                    }
                } else {
                    NavigationLink {
                        ComicDiscoveryWebResourceView(
                            url: self.history.resourceURL,
                            title: self.history.title
                        )
                    } label: {
                        Label("Open Resource", systemImage: "globe")
                    }
                }
            }

            Section("Temporary Detail") {
                LabeledContent("URL", value: self.history.resourceURL.absoluteString)
                if let sourcePageURL: URL = self.history.sourcePageURL {
                    LabeledContent("Source Page", value: sourcePageURL.absoluteString)
                }
                if let matchedKeyword: String = self.history.matchedKeyword {
                    LabeledContent("Keyword", value: matchedKeyword)
                }
            }
        }
        .navigationTitle("Temporary")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
