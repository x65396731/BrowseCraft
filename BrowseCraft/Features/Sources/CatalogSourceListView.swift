import SwiftUI
import BrowseCraftRulesKit

struct CatalogSourceListView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var addingSourceIDs: Set<String> = []
    @State private var failedSourceIDs: Set<String> = []

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(self.viewModel.catalogSources, id: \.id) { catalogSource in
                        CatalogSourceRowView(
                            catalogSource: catalogSource,
                            isAdded: self.viewModel.isCatalogSourceAdded(catalogSource),
                            isAdding: self.addingSourceIDs.contains(catalogSource.id),
                            didFail: self.failedSourceIDs.contains(catalogSource.id),
                            addAction: {
                                self.add(catalogSource)
                            }
                        )
                    }
                }
            }
            .navigationTitle("测试数据")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                }
            }
        }
    }

    private func add(_ catalogSource: BrowseCraftCatalogSource) {
        if self.addingSourceIDs.contains(catalogSource.id)
            || self.viewModel.isCatalogSourceAdded(catalogSource) {
            return
        }

        self.addingSourceIDs.insert(catalogSource.id)
        self.failedSourceIDs.remove(catalogSource.id)

        Task {
            let didAdd: Bool = await self.viewModel.addCatalogSource(catalogSource)
            await MainActor.run {
                self.addingSourceIDs.remove(catalogSource.id)
                if didAdd {
                    self.dismiss()
                } else {
                    self.failedSourceIDs.insert(catalogSource.id)
                }
            }
        }
    }
}

private struct CatalogSourceRowView: View {
    let catalogSource: BrowseCraftCatalogSource
    let isAdded: Bool
    let isAdding: Bool
    let didFail: Bool
    let addAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.catalogSource.name)
                    .font(.body)
                Text(self.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if self.didFail {
                    Text("加载失败")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer(minLength: 12)

            self.trailingControl
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if self.isAdded {
            Label("已添加", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if self.isAdding {
            ProgressView()
        } else {
            Button(
                action: self.addAction,
                label: {
                    Image(systemName: "plus.circle")
                }
            )
            .accessibilityLabel("Add \(self.catalogSource.name)")
        }
    }

    private var subtitle: String {
        return "\(self.kindTitle) · \(self.catalogSource.baseURL)"
    }

    private var kindTitle: String {
        switch self.catalogSource.kind {
        case .comic:
            return "漫画"
        case .rss:
            return "RSS"
        case .video:
            return "视频"
        }
    }
}
