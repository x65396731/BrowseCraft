import SwiftUI

// 中文注释：SourcesView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：SourcesView 是 struct，负责本模块中的对应职责。
struct SourcesView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @State private var isShowingAddSourceView: Bool = false

    var body: some View {
        NavigationView {
            List {
                ForEach(self.viewModel.sources, id: \.id) { source in
                    SourceRowView(
                        source: source,
                        isSelected: source.id == self.viewModel.selectedSourceID,
                        selectAction: {
                            self.viewModel.selectedSourceID = source.id
                        }
                    )
                }
                .onDelete { offsets in
                    self.viewModel.deleteSources(at: offsets)
                }
            }
            .overlay(
                Group {
                if self.viewModel.sources.isEmpty {
                    EmptyStateView(
                        systemImage: "tray",
                        title: "No Sources",
                        message: "Add a JSON site rule before refreshing content."
                    )
                }
                }
            )
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(
                        action: {
                            self.isShowingAddSourceView = true
                        },
                        label: {
                            Image(systemName: "plus")
                        }
                    )
                    .accessibilityLabel("Add Source")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(
                        action: {
                            Task {
                                await self.viewModel.refreshSelectedSource()
                            }
                        },
                        label: {
                            if self.viewModel.isRefreshing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    )
                    .disabled(self.viewModel.selectedSource == nil || self.viewModel.isRefreshing)
                    .accessibilityLabel("Refresh Selected Source")
                }
            }
            .onAppear {
                self.viewModel.load()
            }
            .sheet(isPresented: self.$isShowingAddSourceView) {
                AddSourceView(viewModel: self.viewModel)
            }
            .alert(isPresented: self.errorAlertBinding) {
                Alert(
                    title: Text("Sources"),
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
