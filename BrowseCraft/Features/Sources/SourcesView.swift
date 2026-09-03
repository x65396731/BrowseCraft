import BrowseCraftDomain
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
                    footer: self.sourceListFooter
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
                        Task {
                            await self.viewModel.deleteSources(at: offsets)
                        }
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

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(
                            "\(self.viewModel.occupiedSourceSlotCount) / " +
                                "\(self.viewModel.sourceSlotLimit)"
                        )
                        .font(.headline)
                        .monospacedDigit()

                        Text("Sources Used")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Sources Used")
                    .accessibilityValue(
                        "\(self.viewModel.occupiedSourceSlotCount) of " +
                            "\(self.viewModel.sourceSlotLimit)"
                    )
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
                Task {
                    await self.viewModel.load()
                }
            }
            .onChange(of: self.cloudSyncViewModel.contentRevision) { _, _ in
                Task {
                    await self.viewModel.load()
                }
            }
            .sheet(isPresented: self.$isShowingAddSourceView) {
                AddSourceView(viewModel: self.viewModel)
            }
            .sheet(isPresented: self.$isShowingCatalogSourceListView) {
                CatalogSourceListView(viewModel: self.viewModel)
            }
            .sheet(item: self.slotActivationBinding) { source in
                SourceSlotActivationView(
                    lockedSource: source,
                    activeSources: self.viewModel.activeCustomSources,
                    canActivateWithoutReplacement:
                        self.viewModel.canActivateRequestedSourceWithoutReplacement,
                    activationAction: { replacingSourceID in
                        return await self.viewModel.activateRequestedSource(
                            replacingSourceID: replacingSourceID
                        )
                    }
                )
            }
            .alert(isPresented: self.errorAlertBinding) {
                self.errorAlert()
            }
        }
    }

    @ViewBuilder
    private var sourceListFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Deleting a source also removes its related reading/watch history and library state.")

            if self.viewModel.lockedSourceCount > 0 {
                Text(
                    "\(self.viewModel.lockedSourceCount) restored " +
                        "\(self.viewModel.lockedSourceCount == 1 ? "source is" : "sources are") " +
                        "locked by the current source limit. Tap a locked source to replace an active source."
                )
                .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    private var slotActivationBinding: Binding<Source?> {
        return Binding(
            get: {
                return self.viewModel.requestedSlotActivationSource
            },
            set: { source in
                if source == nil {
                    self.viewModel.dismissRequestedSlotActivation()
                }
            }
        )
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

@MainActor
private struct SourceSlotActivationView: View {
    @Environment(\.dismiss) private var dismiss
    let lockedSource: Source
    let activeSources: [Source]
    let canActivateWithoutReplacement: Bool
    let activationAction: (String?) async -> Bool

    @State private var isActivating: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(self.lockedSource.name)
                            .font(.headline)

                        Text(
                            "This source was restored safely, but it is not currently part of your active source loadout."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if self.canActivateWithoutReplacement {
                    Section {
                        Button("Activate Source") {
                            self.activate(replacingSourceID: nil)
                        }
                    } footer: {
                        Text("An unused source slot is available.")
                    }
                } else {
                    Section {
                        ForEach(self.activeSources, id: \.id) { source in
                            Button {
                                self.activate(replacingSourceID: source.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.name)
                                    Text(source.baseURL)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    } header: {
                        Text("Replace an active source")
                    } footer: {
                        Text(
                            "The replaced source remains safely stored and becomes locked. Purchase more source slots in Settings > Premium to keep more sources active."
                        )
                    }
                }
            }
            .navigationTitle("Activate Source")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(self.isActivating)
            .overlay {
                if self.isActivating {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                }
            }
        }
    }

    private func activate(replacingSourceID: String?) {
        guard self.isActivating == false else {
            return
        }
        self.isActivating = true

        Task {
            _ = await self.activationAction(replacingSourceID)
            self.isActivating = false
            self.dismiss()
        }
    }
}
