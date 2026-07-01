import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        NavigationView {
            List {
                Section("Favorites") {
                    ForEach(self.viewModel.favoriteItems, id: \.id) { item in
                        CompactContentRowView(
                            item: item,
                            subtitle: self.viewModel.sourceName(for: item.sourceId)
                        )
                    }
                }

                Section("Reading") {
                    ForEach(self.viewModel.readingHistory, id: \.id) { history in
                        if let item: ContentItem = self.viewModel.item(for: history) {
                            CompactContentRowView(
                                item: item,
                                subtitle: Self.historyDateFormatter.string(from: history.updatedAt)
                            )
                        }
                    }
                }
            }
            .overlay(
                Group {
                if self.viewModel.favoriteItems.isEmpty && self.viewModel.readingHistory.isEmpty {
                    EmptyStateView(
                        systemImage: "clock",
                        title: "No History",
                        message: "Opened and favorited items will appear here."
                    )
                }
                }
            )
            .navigationTitle("History")
            .onAppear {
                self.viewModel.load()
            }
            .alert(isPresented: self.errorAlertBinding) {
                Alert(
                    title: Text("History"),
                    message: Text(self.viewModel.errorMessage ?? ""),
                    dismissButton: .default(
                        Text("OK"),
                        action: {
                            self.viewModel.errorMessage = nil
                        }
                    )
                )
            }
        }
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var errorAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.errorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.errorMessage = nil
                }
            }
        )
    }
}
