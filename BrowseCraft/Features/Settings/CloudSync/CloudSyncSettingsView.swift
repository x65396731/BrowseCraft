import SwiftUI

@MainActor
struct CloudSyncSettingsView: View {
    @ObservedObject var viewModel: CloudSyncSettingsViewModel

    var body: some View {
        Form {
            self.accountSection
            self.syncPreferenceSection
            self.syncContentSection

            if self.viewModel.isCloudSyncEnabled {
                self.syncActionSection
            }

            if let result: CloudSyncRunResult = self.viewModel.lastResult {
                self.lastSyncSection(result: result)
            }

            if let errorMessage: String = self.viewModel.errorMessage {
                self.errorSection(message: errorMessage)
            }
        }
        .navigationTitle("Cloud Sync")
        .task {
            await self.viewModel.start()
        }
        .sheet(item: self.firstEnableRequestBinding) { request in
            CloudSyncFirstEnableSheet(
                viewModel: self.viewModel,
                request: request
            )
            .presentationDetents([.medium, .large])
        }
        .alert(item: self.activationIssueBinding) { issue in
            Alert(
                title: Text(self.activationIssueTitle(issue)),
                message: Text(self.activationIssueMessage(issue)),
                primaryButton: .default(Text("Check Again")) {
                    Task {
                        await self.viewModel.setCloudSyncEnabled(true)
                    }
                },
                secondaryButton: .cancel(Text("Not Now")) {
                    self.viewModel.dismissActivationIssue()
                }
            )
        }
    }

    private var accountSection: some View {
        Section("iCloud Account") {
            HStack(spacing: 12) {
                Image(systemName: self.accountStatusIcon)
                    .font(.title2)
                    .foregroundStyle(self.accountStatusColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(self.accountStatusTitle)
                        .font(.body.weight(.medium))
                    Text(self.accountStatusDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if self.viewModel.accountAvailability == .checking ||
                    self.viewModel.isRefreshingAccount {
                    ProgressView()
                }
            }

            Button {
                Task {
                    await self.viewModel.refreshAccount()
                }
            } label: {
                Label("Refresh iCloud Status", systemImage: "arrow.clockwise")
            }
            .disabled(self.viewModel.isRefreshingAccount)
        }
    }

    private var syncPreferenceSection: some View {
        Section {
            Toggle(isOn: self.cloudSyncEnabledBinding) {
                HStack(spacing: 8) {
                    Text("Cloud Sync")
                    if self.viewModel.isChangingCloudSyncEnabled {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(self.viewModel.canChangeCloudSyncEnabled == false)
            .onChange(of: self.viewModel.isCloudSyncEnabled) { _, newValue in
                AppAnalytics.shared.logSettingChanged(
                    name: "cloud_sync",
                    value: String(newValue)
                )
            }
        } footer: {
            Text(self.syncPreferenceFooter)
        }
    }

    private var syncContentSection: some View {
        Section("Synced Content") {
            self.syncScopeRow(
                title: "Custom Sources",
                systemImage: "rectangle.stack",
                isIncluded: true
            )
            self.syncScopeRow(
                title: "Favorites",
                systemImage: "heart",
                isIncluded: true
            )
            self.syncScopeRow(
                title: "Reading Progress",
                systemImage: "book.pages",
                isIncluded: false
            )
        }
    }

    private var syncActionSection: some View {
        Section {
            Button {
                Task {
                    await self.viewModel.synchronizeNow()
                }
            } label: {
                HStack {
                    Label(
                        self.viewModel.isSynchronizing ? "Syncing…" : "Sync Now",
                        systemImage: "arrow.triangle.2.circlepath.icloud"
                    )
                    Spacer()
                    if self.viewModel.isSynchronizing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(self.viewModel.canSynchronizeNow == false)
        } footer: {
            Text("Sync downloads and merges iCloud changes before uploading pending local changes.")
        }
    }

    private func lastSyncSection(result: CloudSyncRunResult) -> some View {
        Section("Last Sync") {
            LabeledContent(
                "Completed",
                value: result.finishedAt.formatted(date: .abbreviated, time: .standard)
            )
            LabeledContent("Uploaded", value: String(result.uploadedCount))
            LabeledContent("Downloaded", value: String(result.downloadedCount))
            LabeledContent("Deleted", value: String(result.deletedCount))
            LabeledContent("Skipped", value: String(result.skippedCount))
            LabeledContent("Failed", value: String(result.failedCount))
        }
    }

    private func errorSection(message: String) -> some View {
        Section {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .textSelection(.enabled)

            if self.viewModel.isCloudSyncEnabled {
                Button {
                    Task {
                        await self.viewModel.retrySynchronization()
                    }
                } label: {
                    Label("Retry Sync", systemImage: "arrow.clockwise")
                }
                .disabled(self.viewModel.canSynchronizeNow == false)
            }
        } header: {
            Label("Cloud Sync Error", systemImage: "exclamationmark.triangle")
        } footer: {
            Text("Sensitive request values are never included in Cloud Sync error messages.")
        }
    }

    private func syncScopeRow(
        title: String,
        systemImage: String,
        isIncluded: Bool
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Label(
                isIncluded ? "Included" : "Not Yet Supported",
                systemImage: isIncluded ? "checkmark.circle.fill" : "minus.circle"
            )
            .font(.footnote)
            .foregroundStyle(isIncluded ? Color.green : Color.secondary)
            .labelStyle(.titleAndIcon)
        }
    }

    private var cloudSyncEnabledBinding: Binding<Bool> {
        return Binding(
            get: {
                return self.viewModel.isCloudSyncEnabled
            },
            set: { enabled in
                Task {
                    await self.viewModel.setCloudSyncEnabled(enabled)
                }
            }
        )
    }

    private var firstEnableRequestBinding: Binding<CloudSyncSettingsViewModel.FirstEnableRequest?> {
        return Binding(
            get: {
                return self.viewModel.firstEnableRequest
            },
            set: { request in
                if request == nil {
                    self.viewModel.cancelFirstEnable()
                }
            }
        )
    }

    private var activationIssueBinding: Binding<CloudSyncSettingsViewModel.ActivationIssue?> {
        return Binding(
            get: {
                return self.viewModel.activationIssue
            },
            set: { issue in
                if issue == nil {
                    self.viewModel.dismissActivationIssue()
                }
            }
        )
    }

    private var accountStatusTitle: String {
        switch self.viewModel.accountAvailability {
        case .notChecked:
            return "iCloud Not Checked"
        case .checking:
            return "Checking iCloud"
        case .available:
            return "iCloud Available"
        case .noAccount:
            return "Not Signed In"
        case .restricted:
            return "iCloud Restricted"
        case .temporarilyUnavailable:
            return "Temporarily Unavailable"
        case .couldNotDetermine:
            return "Status Unavailable"
        }
    }

    private var accountStatusDetail: String {
        switch self.viewModel.accountAvailability {
        case .notChecked:
            return "Turn on Cloud Sync to check the iCloud account on this device."
        case .checking:
            return "Checking the iCloud account configured on this device."
        case .available:
            return "Private CloudKit storage is available for this account."
        case .noAccount:
            return "Sign in to iCloud in System Settings to use Cloud Sync."
        case .restricted:
            return "iCloud access may be limited by parental controls or device management."
        case .temporarilyUnavailable:
            return "Local data and pending changes are preserved until iCloud recovers."
        case .couldNotDetermine:
            return "The iCloud account status could not be determined. Try refreshing."
        }
    }

    private var accountStatusIcon: String {
        switch self.viewModel.accountAvailability {
        case .notChecked:
            return "icloud"
        case .checking:
            return "icloud"
        case .available:
            return "checkmark.icloud.fill"
        case .noAccount:
            return "icloud.slash"
        case .restricted, .temporarilyUnavailable:
            return "exclamationmark.triangle"
        case .couldNotDetermine:
            return "questionmark.circle"
        }
    }

    private var accountStatusColor: Color {
        switch self.viewModel.accountAvailability {
        case .available:
            return .green
        case .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine:
            return .orange
        case .notChecked, .checking:
            return .accentColor
        }
    }

    private var syncPreferenceFooter: String {
        switch self.viewModel.accountAvailability {
        case .notChecked:
            return "Turning on Cloud Sync starts an iCloud account check and shows what will be synchronized before any cloud data is loaded."
        case .checking:
            return "Cloud Sync will be available after the iCloud account check completes."
        case .available:
            return "When disabled, local data and pending upload tasks are retained. Nothing is deleted from iCloud."
        case .noAccount:
            return "The app remains available offline in its local data space."
        case .restricted:
            return "Cloud Sync cannot be enabled while iCloud access is restricted."
        case .temporarilyUnavailable:
            return "Sync is paused. Local data and pending upload tasks remain unchanged."
        case .couldNotDetermine:
            return "Refresh the iCloud status before enabling Cloud Sync."
        }
    }

    private func activationIssueTitle(
        _ issue: CloudSyncSettingsViewModel.ActivationIssue
    ) -> String {
        switch issue {
        case .signInRequired:
            return "Sign In to iCloud"
        case .restricted:
            return "iCloud Is Restricted"
        case .temporarilyUnavailable:
            return "iCloud Is Temporarily Unavailable"
        case .statusUnavailable:
            return "Unable to Check iCloud"
        }
    }

    private func activationIssueMessage(
        _ issue: CloudSyncSettingsViewModel.ActivationIssue
    ) -> String {
        switch issue {
        case .signInRequired:
            return "Open the Settings app, sign in to your Apple Account, and enable iCloud Drive. Then return here and check again."
        case .restricted:
            return "iCloud access is limited by parental controls or device management settings."
        case .temporarilyUnavailable:
            return "Your local data is unchanged. Wait for iCloud to recover, then check again."
        case .statusUnavailable:
            return "The iCloud account status could not be determined. Check your connection and try again."
        }
    }
}

@MainActor
private struct CloudSyncFirstEnableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CloudSyncSettingsViewModel
    let request: CloudSyncSettingsViewModel.FirstEnableRequest

    @State private var isSubmitting: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Cloud Sync stores supported app data in the private CloudKit database of the iCloud account configured on this device.")
                }

                Section("Synced Content") {
                    Label("Custom Sources", systemImage: "rectangle.stack")
                    Label("Favorites", systemImage: "heart")
                    Label("Reading Progress — Not Included", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                }

                if self.request.localDataSummary.hasMergeableData {
                    Section("Local Data") {
                        LabeledContent(
                            "Custom Sources",
                            value: String(self.request.localDataSummary.sourceCount)
                        )
                        LabeledContent(
                            "Favorites",
                            value: String(self.request.localDataSummary.favoriteItemCount)
                        )
                    }

                    Section {
                        Button {
                            self.submit(decision: .mergeLocalData)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Merge Local Data", systemImage: "arrow.triangle.merge")
                                Text("Copy local sources and favorites into this iCloud account, then sync.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(self.isSubmitting)

                        Button {
                            self.submit(decision: .useCloudDataOnly)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Use iCloud Data Only", systemImage: "icloud")
                                Text("Leave local data in its current space and restore this account from iCloud.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(self.isSubmitting)
                    } footer: {
                        Text("Neither choice deletes the existing local data.")
                    }
                } else {
                    Section {
                        Button {
                            self.submit(decision: .useCloudDataOnly)
                        } label: {
                            Label("Enable Cloud Sync", systemImage: "checkmark.icloud")
                        }
                        .disabled(self.isSubmitting)
                    } footer: {
                        Text("No local sources or favorites need to be merged. Nothing is uploaded until you confirm.")
                    }
                }

                if self.isSubmitting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Preparing Cloud Sync…")
                        }
                    }
                }

                if let errorMessage: String = self.viewModel.actionErrorMessage {
                    Section("Setup Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("First Cloud Sync")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(self.isSubmitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.viewModel.cancelFirstEnable()
                        self.dismiss()
                    }
                    .disabled(self.isSubmitting)
                }
            }
        }
    }

    private func submit(decision: CloudAccountLocalDataDecision) {
        guard self.isSubmitting == false else {
            return
        }
        self.isSubmitting = true

        Task {
            await self.viewModel.confirmFirstEnable(decision: decision)
            self.isSubmitting = false
            if self.viewModel.firstEnableRequest == nil {
                self.dismiss()
            }
        }
    }
}
