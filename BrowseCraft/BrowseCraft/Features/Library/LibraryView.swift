import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 14)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: self.gridColumns, spacing: 16) {
                    ForEach(self.viewModel.items, id: \.id) { item in
                        ContentCardView(
                            item: item,
                            sourceName: self.viewModel.sourceName(for: item.sourceId),
                            isFavorite: self.viewModel.favoriteItemIDs.contains(item.id),
                            favoriteAction: {
                                self.viewModel.toggleFavorite(item: item)
                            },
                            openAction: {
                                self.viewModel.recordOpened(item: item)
                            }
                        )
                    }
                }
                .padding(16)
            }
            .overlay(
                Group {
                if self.viewModel.items.isEmpty {
                    EmptyStateView(
                        systemImage: "square.grid.2x2",
                        title: "No Items",
                        message: "Refresh a source to fill your library."
                    )
                }
                }
            )
            .navigationTitle("Library")
            .onAppear {
                self.viewModel.load()
            }
            .alert(isPresented: self.errorAlertBinding) {
                Alert(
                    title: Text("Library"),
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
