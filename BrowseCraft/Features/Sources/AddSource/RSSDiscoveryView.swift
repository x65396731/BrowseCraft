import Foundation
import SwiftUI

struct RSSDiscoveryView: View {
    private enum OperationState: Equatable {
        case idle
        case searching
        case saving(String)
        case saved
        case error(String)

        var isWorking: Bool {
            switch self {
            case .searching, .saving:
                return true
            case .idle, .saved, .error:
                return false
            }
        }
    }

    @ObservedObject var viewModel: SourcesViewModel
    let completion: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var websiteURL: String = ""
    @State private var results: [DiscoveredRSSFeedItem] = []
    @State private var operationState: OperationState = .idle

    var body: some View {
        NavigationStack {
            Form {
                Section("Website") {
                    TextField("URL", text: self.$websiteURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disabled(self.operationState.isWorking)
                }

                Section {
                    Button("Search RSS") {
                        Task {
                            await self.search()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(self.canSearch == false)
                }

                if let statusMessage: String = self.statusMessage {
                    Section("Status") {
                        Text(statusMessage)
                            .foregroundStyle(self.statusForegroundStyle)
                    }
                }

                if self.results.isEmpty == false {
                    Section("Feeds") {
                        ForEach(self.results) { item in
                            self.feedRow(item)
                        }
                    }
                }
            }
            .navigationTitle("RSS Feed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                    .disabled(self.operationState.isWorking)
                }
            }
        }
    }

    private var trimmedWebsiteURL: String {
        return self.websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSearch: Bool {
        return self.trimmedWebsiteURL.isEmpty == false
            && self.operationState.isWorking == false
    }

    private var statusMessage: String? {
        switch self.operationState {
        case .idle:
            return self.results.isEmpty ? "Enter a website URL, then search for RSS or Atom feeds." : nil
        case .searching:
            return "Searching for RSS feeds..."
        case .saving:
            return "Saving RSS source..."
        case .saved:
            return "RSS source saved."
        case .error(let message):
            return message
        }
    }

    private var statusForegroundStyle: Color {
        switch self.operationState {
        case .error:
            return .red
        case .saved:
            return .green
        case .idle, .searching, .saving:
            return .secondary
        }
    }

    @ViewBuilder
    private func feedRow(_ item: DiscoveredRSSFeedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.feedURL.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("\(item.itemCount) items")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button("Add") {
                    Task {
                        await self.save(item)
                    }
                }
                .disabled(self.operationState.isWorking)
            }

            if let firstItemTitle: String = item.firstItemTitle {
                Text(firstItemTitle)
                    .font(.footnote)
                    .foregroundStyle(.blue)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    @MainActor
    private func search() async {
        self.operationState = .searching
        let discovered: [DiscoveredRSSFeedItem] = await self.viewModel.discoverRSSFeeds(
            siteURLString: self.trimmedWebsiteURL
        )
        self.results = discovered

        if discovered.isEmpty {
            self.operationState = .error(
                self.viewModel.errorMessage ?? "No RSS or Atom feed was found on this website."
            )
        } else {
            self.operationState = .idle
        }
    }

    @MainActor
    private func save(_ item: DiscoveredRSSFeedItem) async {
        self.operationState = .saving(item.id)
        let source: Source? = await self.viewModel.addRSSSource(
            feedURLString: item.feedURL.absoluteString,
            name: item.title
        )

        guard source != nil else {
            self.operationState = .error(self.viewModel.errorMessage ?? "Failed to save RSS source.")
            return
        }

        self.operationState = .saved
        self.completion()
        self.dismiss()
    }
}
