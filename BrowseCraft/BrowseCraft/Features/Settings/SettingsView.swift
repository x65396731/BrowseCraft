import SwiftUI

// 中文注释：SettingsView.swift 属于用户设置功能层，集中承载账号、同步、缓存和应用信息入口。

/// 中文注释：SettingsView 是应用的用户设置页。
struct SettingsView: View {
    @AppStorage("settings.displayName") private var displayName: String = "Reader"
    @AppStorage("settings.email") private var email: String = ""
    @AppStorage("settings.cloudSyncEnabled") private var isCloudSyncEnabled: Bool = false
    @AppStorage("settings.syncBookmarks") private var shouldSyncBookmarks: Bool = true
    @AppStorage("settings.syncReadingProgress") private var shouldSyncReadingProgress: Bool = true
    @AppStorage("settings.cacheOverCellular") private var allowsCacheOverCellular: Bool = false
    @AppStorage("settings.imageCacheLimit") private var imageCacheLimit: Int = 512

    @State private var isShowingClearCacheAlert: Bool = false
    @State private var isShowingRatingAlert: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink(
                        destination: ProfileSettingsView(
                            displayName: self.$displayName,
                            email: self.$email
                        )
                    ) {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 42))
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Reader" : self.displayName)
                                    .font(.headline)

                                Text(self.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add profile details" : self.email)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Account") {
                    NavigationLink(destination: CloudSyncSettingsView(
                        isCloudSyncEnabled: self.$isCloudSyncEnabled,
                        shouldSyncBookmarks: self.$shouldSyncBookmarks,
                        shouldSyncReadingProgress: self.$shouldSyncReadingProgress
                    )) {
                        SettingsRow(
                            systemImage: "icloud",
                            title: "Cloud Sync",
                            detail: self.isCloudSyncEnabled ? "On" : "Off"
                        )
                    }

                    NavigationLink(destination: BookmarksSettingsView()) {
                        SettingsRow(
                            systemImage: "bookmark",
                            title: "Bookmarks",
                            detail: "Favorites and saved items"
                        )
                    }

                    NavigationLink(destination: PremiumSettingsView()) {
                        SettingsRow(
                            systemImage: "sparkles",
                            title: "Premium",
                            detail: "Unlock paid features"
                        )
                    }
                }

                Section("Storage") {
                    NavigationLink(destination: CacheSettingsView(
                        allowsCacheOverCellular: self.$allowsCacheOverCellular,
                        imageCacheLimit: self.$imageCacheLimit,
                        clearCacheAction: {
                            self.isShowingClearCacheAlert = true
                        }
                    )) {
                        SettingsRow(
                            systemImage: "externaldrive",
                            title: "Cache",
                            detail: "\(self.imageCacheLimit) MB"
                        )
                    }
                }

                Section("App") {
                    SettingsRow(
                        systemImage: "number",
                        title: "Version",
                        detail: Self.versionText
                    )

                    Button(
                        action: {
                            self.isShowingRatingAlert = true
                        },
                        label: {
                            SettingsRow(
                                systemImage: "star",
                                title: "Rate BrowseCraft",
                                detail: nil
                            )
                        }
                    )
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Settings")
            .alert("Cache", isPresented: self.$isShowingClearCacheAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Cache clearing is ready for wiring to the cache service.")
            }
            .alert("Rate BrowseCraft", isPresented: self.$isShowingRatingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("App Store rating will be available after the App Store product ID is configured.")
            }
        }
    }

    private static var versionText: String {
        let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct SettingsRow: View {
    let systemImage: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: self.systemImage)
                .font(.body)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            Text(self.title)

            Spacer()

            if let detail: String = self.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct ProfileSettingsView: View {
    @Binding var displayName: String
    @Binding var email: String

    var body: some View {
        Form {
            Section("Personal Profile") {
                TextField("Display Name", text: self.$displayName)
                    .textInputAutocapitalization(.words)

                TextField("Email", text: self.$email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("Profile")
    }
}

private struct CloudSyncSettingsView: View {
    @Binding var isCloudSyncEnabled: Bool
    @Binding var shouldSyncBookmarks: Bool
    @Binding var shouldSyncReadingProgress: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Cloud Sync", isOn: self.$isCloudSyncEnabled)
            } footer: {
                Text("Cloud sync stores account data, bookmarks, and reading progress when the sync service is connected.")
            }

            Section("Sync Content") {
                Toggle("Bookmarks", isOn: self.$shouldSyncBookmarks)
                    .disabled(self.isCloudSyncEnabled == false)

                Toggle("Reading Progress", isOn: self.$shouldSyncReadingProgress)
                    .disabled(self.isCloudSyncEnabled == false)
            }
        }
        .navigationTitle("Cloud Sync")
    }
}

private struct BookmarksSettingsView: View {
    var body: some View {
        List {
            Section {
                Label("Favorites are managed from History.", systemImage: "heart")
                Label("Saved bookmark folders can be added after the bookmark model is introduced.", systemImage: "folder")
            }
        }
        .navigationTitle("Bookmarks")
    }
}

private struct PremiumSettingsView: View {
    var body: some View {
        List {
            Section("Premium Service") {
                Label("Cloud sync across devices", systemImage: "icloud")
                Label("Larger cache limits", systemImage: "externaldrive")
                Label("Future AI rule assistant", systemImage: "sparkles")
            }

            Section {
                Button("Open Premium") {}
                    .disabled(true)
            } footer: {
                Text("Paid service wiring will be added after product IDs and entitlement checks are ready.")
            }
        }
        .navigationTitle("Premium")
    }
}

private struct CacheSettingsView: View {
    @Binding var allowsCacheOverCellular: Bool
    @Binding var imageCacheLimit: Int
    let clearCacheAction: () -> Void

    var body: some View {
        Form {
            Section("Cache Policy") {
                Stepper(
                    value: self.$imageCacheLimit,
                    in: 128...4096,
                    step: 128
                ) {
                    SettingsRow(
                        systemImage: "photo.stack",
                        title: "Image Cache Limit",
                        detail: "\(self.imageCacheLimit) MB"
                    )
                }

                Toggle("Cache Over Cellular", isOn: self.$allowsCacheOverCellular)
            }

            Section {
                Button(
                    role: .destructive,
                    action: self.clearCacheAction,
                    label: {
                        Label("Clear Cache", systemImage: "trash")
                    }
                )
            }
        }
        .navigationTitle("Cache")
    }
}

#Preview {
    SettingsView()
}
