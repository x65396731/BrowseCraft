import SwiftUI

// 中文注释：SourcesView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：SourcesView 是 struct，负责本模块中的对应职责。
struct SourcesView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @State private var isShowingAddSourceView: Bool = false
    @State private var isShowingImportRulePackageView: Bool = false

    var body: some View {
        NavigationView {
            List {
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
                            destination: RuleDetailView(
                                viewModel: self.viewModel,
                                sourceID: source.id
                            )
                        ) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                        .accessibilityLabel("Rule Details")
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
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(
                        action: {
                            self.isShowingAddSourceView = true
                        },
                        label: {
                            Image(systemName: "plus")
                        }
                    )
                    .accessibilityLabel("Add Source")

                    Button(
                        action: {
                            self.isShowingImportRulePackageView = true
                        },
                        label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    )
                    .accessibilityLabel("Import Rule Package")
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
            .sheet(isPresented: self.$isShowingImportRulePackageView) {
                ImportRulePackageView(viewModel: self.viewModel)
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
}

private struct ImportRulePackageView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var packageJSON: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Rule Package JSON") {
                    TextEditor(text: self.$packageJSON)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 260)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Import Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if self.viewModel.importRulePackage(packageJSON: self.packageJSON) != nil {
                            self.dismiss()
                        }
                    }
                    .disabled(self.packageJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
