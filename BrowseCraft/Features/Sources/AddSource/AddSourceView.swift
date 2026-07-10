import Foundation
import SwiftUI

// 中文注释：AddSourceView.swift 是中性的添加来源入口，具体导入能力由 SourceImportOption 决定。

struct AddSourceView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var runtimeSourceKind: RuntimeSourceImportKind?
    @State private var isShowingComicDiscovery: Bool = false
    @State private var isShowingVideoDiscovery: Bool = false
    @State private var isShowingRSSDiscovery: Bool = false
    @State private var unavailableOption: SourceImportOptionKind?

    private let options: [SourceImportOption] = SourceImportOption.defaultOptions

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    self.optionButton(for: .comicSource)
                    self.optionButton(for: .videoSource)
                    self.optionButton(for: .rssFeedURL)
                }
            }
            .navigationTitle("Add Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                }
            }
            .sheet(isPresented: self.$isShowingComicDiscovery) {
                ComicDiscoveryView(viewModel: self.viewModel)
            }
            .sheet(isPresented: self.$isShowingVideoDiscovery) {
                VideoDiscoveryView(viewModel: self.viewModel)
            }
            .sheet(isPresented: self.$isShowingRSSDiscovery) {
                RSSDiscoveryView(
                    viewModel: self.viewModel,
                    completion: {
                        self.dismiss()
                    }
                )
            }
            .sheet(item: self.$runtimeSourceKind) { kind in
                RuntimeSourceImportView(
                    viewModel: self.viewModel,
                    kind: kind,
                    completion: {
                        self.dismiss()
                    }
                )
            }
            .alert(
                "Source Type Unavailable",
                isPresented: self.unavailableOptionBinding,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(self.unavailableOptionMessage)
                }
            )
        }
    }

    @ViewBuilder
    private func optionButton(for kind: SourceImportOptionKind) -> some View {
        if let option: SourceImportOption = self.options.first(where: { item in item.kind == kind }) {
            Button(
                action: {
                    self.select(option)
                },
                label: {
                    Label(
                        option.kind.displayTitle,
                        systemImage: option.kind.systemImageName
                    )
                }
            )
        }
    }

    private func select(_ option: SourceImportOption) {
        switch option.kind {
        case .comicSource:
            self.isShowingComicDiscovery = true
        case .videoSource:
            self.isShowingVideoDiscovery = true
        case .rssFeedURL:
            self.isShowingRSSDiscovery = true
        case .scriptSource:
            self.unavailableOption = option.kind
        }
    }

    private var unavailableOptionBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.unavailableOption != nil
            },
            set: { newValue in
                if newValue == false {
                    self.unavailableOption = nil
                }
            }
        )
    }

    private var unavailableOptionMessage: String {
        switch self.unavailableOption {
        case .comicSource:
            return "Comic sources can be added from the Comics source form."
        case .videoSource:
            return "Video sources can be added from the Video source form."
        case .scriptSource:
            return "Script Source is closed. Use Website Rule JSON or URL-based source search instead."
        case .rssFeedURL, nil:
            return "This source type is not available yet."
        }
    }
}

private extension SourceImportOptionKind {
    var displayTitle: String {
        switch self {
        case .comicSource:
            return "Comics"
        case .videoSource:
            return "Video"
        case .rssFeedURL:
            return "RSS Feed"
        case .scriptSource:
            return "Script Source"
        }
    }

    var systemImageName: String {
        switch self {
        case .comicSource:
            return "book.pages"
        case .videoSource:
            return "play.rectangle"
        case .rssFeedURL:
            return "dot.radiowaves.left.and.right"
        case .scriptSource:
            return "terminal"
        }
    }
}
