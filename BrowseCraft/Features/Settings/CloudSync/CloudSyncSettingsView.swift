import SwiftUI

struct CloudSyncSettingsView: View {
    @Binding var isCloudSyncEnabled: Bool
    @Binding var shouldSyncBookmarks: Bool
    @Binding var shouldSyncReadingProgress: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Cloud Sync", isOn: self.$isCloudSyncEnabled)
                    .onChange(of: self.isCloudSyncEnabled) { _, newValue in
                        AppAnalytics.shared.logSettingChanged(
                            name: "cloud_sync",
                            value: String(newValue)
                        )
                    }
            } footer: {
                Text("Cloud sync stores account data, bookmarks, and reading progress when the sync service is connected.")
            }

            Section("Sync Content") {
                Toggle("Bookmarks", isOn: self.$shouldSyncBookmarks)
                    .disabled(self.isCloudSyncEnabled == false)
                    .onChange(of: self.shouldSyncBookmarks) { _, newValue in
                        AppAnalytics.shared.logSettingChanged(
                            name: "sync_bookmarks",
                            value: String(newValue)
                        )
                    }

                Toggle("Reading Progress", isOn: self.$shouldSyncReadingProgress)
                    .disabled(self.isCloudSyncEnabled == false)
                    .onChange(of: self.shouldSyncReadingProgress) { _, newValue in
                        AppAnalytics.shared.logSettingChanged(
                            name: "sync_reading_progress",
                            value: String(newValue)
                        )
                    }
            }
        }
        .navigationTitle("Cloud Sync")
    }
}
