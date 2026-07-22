import SwiftUI

// 中文注释：SourcesView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：SourcesView 是 struct，负责本模块中的对应职责。
@MainActor
struct SourcesView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @ObservedObject var cloudSyncViewModel: CloudSyncSettingsViewModel
    @State private var isShowingAddSourceView: Bool = false
    @State private var isShowingCatalogSourceListView: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section(
                    footer: Text("Deleting a source also removes its related reading/watch history and library state.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                ) {
                    ForEach(self.viewModel.sources, id: \.id) { source in
                        HStack(spacing: 8) {
                            SourceRowView(
                                source: source,
                                isSelected: source.id == self.viewModel.selectedSourceID,
                                isLoading: source.id == self.viewModel.refreshingSourceID,
                                isDisabled: self.viewModel.isRefreshing,
                                selectAction: {
                                    Task {
                                        await self.viewModel.selectSourceAfterRefresh(source)
                                    }
                                }
                            )
                            .layoutPriority(1)

                            NavigationLink(
                                destination: SourceDebugView(
                                    viewModel: self.viewModel,
                                    sourceID: source.id
                                )
                            ) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityLabel("Source Debug")
                        }
                        .listRowInsets(
                            EdgeInsets(
                                top: 8,
                                leading: 16,
                                bottom: 8,
                                trailing: 16
                            )
                        )
                    }
                    .onDelete { offsets in
                        self.viewModel.deleteSources(at: offsets)
                    }
                }
            }
            .overlay(
                Group {
                    if self.shouldShowInitialRestore {
                        CloudSyncInitialRestoreView(
                            state: self.cloudSyncViewModel.initialRestoreState,
                            retryAction: {
                                await self.cloudSyncViewModel.retrySynchronization()
                            }
                        )
                    } else if self.viewModel.sources.isEmpty {
                        EmptyStateView(
                            systemImage: "tray",
                            title: "No Sources",
                            message: "Add a source before refreshing content."
                        )
                    }
                }
            )
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(
                        action: {
                            self.isShowingCatalogSourceListView = true
                        },
                        label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                    )
                    .accessibilityLabel("Source Catalog")

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
                CrashDiagnostics.shared.setScreen(.sourceList)
                AppAnalytics.shared.logScreenView(.sourceList)
                DispatchQueue.main.async {
                    self.viewModel.load()
                }
            }
            .onChange(of: self.cloudSyncViewModel.contentRevision) { _, _ in
                self.viewModel.load()
            }
            .sheet(isPresented: self.$isShowingAddSourceView) {
                AddSourceView(viewModel: self.viewModel)
            }
            .sheet(isPresented: self.$isShowingCatalogSourceListView) {
                CatalogSourceListView(viewModel: self.viewModel)
            }
            .alert(isPresented: self.errorAlertBinding) {
                self.errorAlert()
            }
        }
    }

    private func errorAlert() -> Alert {
        if self.viewModel.canRetryFailedRefresh {
            return Alert(
                title: Text("Sources"),
                message: Text(self.viewModel.errorMessage ?? ""),
                primaryButton: .default(
                    Text("Retry"),
                    action: {
                        Task {
                            await self.viewModel.retryFailedRefresh()
                        }
                    }
                ),
                secondaryButton: .cancel(
                    Text("Cancel"),
                    action: {
                        self.viewModel.clearError()
                    }
                )
            )
        }

        return Alert(
            title: Text("Sources"),
            message: Text(self.viewModel.errorMessage ?? ""),
            dismissButton: .default(
                Text("OK"),
                action: {
                    self.viewModel.clearError()
                }
            )
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.errorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.clearError()
                }
            }
        )
    }

    private var shouldShowInitialRestore: Bool {
        let hasCustomSources: Bool = self.viewModel.sources.contains { source in
            return source.id.hasPrefix("built-in.") == false
        }
        return hasCustomSources == false &&
            self.cloudSyncViewModel.initialRestoreState.shouldReplaceEmptyState
    }

}
