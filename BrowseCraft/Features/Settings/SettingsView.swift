import StoreKit
import SwiftUI
import UIKit

// 中文注释：SettingsView.swift 属于用户设置功能层，集中承载账号、同步、缓存和应用信息入口。

/// 中文注释：SettingsView 是应用的用户设置页。
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var adPlaybackViewModel: AdPlaybackViewModel = AdPlaybackViewModel()
    @AppStorage("settings.displayName") private var displayName: String = "Reader"
    @AppStorage("settings.email") private var email: String = ""
    @AppStorage("settings.cloudSyncEnabled") private var isCloudSyncEnabled: Bool = false
    @AppStorage("settings.syncBookmarks") private var shouldSyncBookmarks: Bool = true
    @AppStorage("settings.syncReadingProgress") private var shouldSyncReadingProgress: Bool = true
    @AppStorage(CrashDiagnostics.collectionEnabledDefaultsKey) private var isDiagnosticsEnabled: Bool = CrashDiagnostics.isCollectionEnabled

    @State private var isShowingInAppPurchase: Bool = false
    @State private var isShowingRatingAlert: Bool = false

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
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

                    Button(
                        action: {
                            self.isShowingInAppPurchase = true
                        },
                        label: {
                            SettingsRow(
                                systemImage: "sparkles",
                                title: "Premium",
                                detail: "Unlock paid features"
                            )
                        }
                    )
                    .buttonStyle(.plain)

                    Button(
                        action: {
                            Task {
                                await self.adPlaybackViewModel.loadAndShow()
                            }
                        },
                        label: {
                            SettingsRow(
                                systemImage: "play.rectangle.on.rectangle",
                                title: self.adPlaybackViewModel.isLoading ? "Starting Ad Service" : "Start Ad Service",
                                detail: self.adPlaybackViewModel.isLoading ? "Loading" : nil
                            )
                        }
                    )
                    .disabled(self.adPlaybackViewModel.isLoading)
                }

                Section("Storage") {
                    NavigationLink(destination: CacheSettingsView(
                        selectedImageCacheLimit: self.imageCacheLimitBinding,
                        clearCacheAction: {
                            self.viewModel.clearImageCache()
                        }
                    )) {
                        SettingsRow(
                            systemImage: "externaldrive",
                            title: "Cache",
                            detail: self.viewModel.imageCacheSettings.displayTitle
                        )
                    }
                }

                Section(
                    content: {
                        Toggle(isOn: self.$isDiagnosticsEnabled) {
                            SettingsRow(
                                systemImage: "waveform.path.ecg",
                                title: "Send Crash Diagnostics",
                                detail: self.isDiagnosticsEnabled ? "On" : "Off"
                            )
                        }
                        .onChange(of: self.isDiagnosticsEnabled) { _, newValue in
                            CrashDiagnostics.shared.setCollectionEnabled(newValue)
                            AppAnalytics.shared.logSettingChanged(
                                name: "crash_diagnostics",
                                value: String(newValue)
                            )
                        }

                        SettingsRow(
                            systemImage: "stethoscope",
                            title: "Diagnostic Code",
                            detail: self.viewModel.diagnosticCode
                        )
                        .contextMenu {
                            Button("Copy") {
                                UIPasteboard.general.string = self.viewModel.diagnosticCode
                            }
                        }

                        Button(
                            action: {
                                UIPasteboard.general.string = self.viewModel.diagnosticCode
                            },
                            label: {
                                SettingsRow(
                                    systemImage: "doc.on.doc",
                                    title: "Copy Diagnostic Code",
                                    detail: nil
                                )
                            }
                        )
                        .buttonStyle(.plain)
                    },
                    footer: {
                        Text("Diagnostic reports include the code above, app version, device model, current screen, source, stage, and selected non-crash errors. They do not include cookies, tokens, full HTML, or full URL query values.")
                    }
                )

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
                                title: "Rate AnyPortal",
                                detail: nil
                            )
                        }
                    )
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Settings")
            .alert("Rate AnyPortal", isPresented: self.$isShowingRatingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("App Store rating will be available after the App Store product ID is configured.")
            }
            .alert("Cache", isPresented: self.cacheStatusAlertBinding) {
                Button("OK", role: .cancel) {
                    self.viewModel.cacheStatusMessage = nil
                }
            } message: {
                Text(self.viewModel.cacheStatusMessage ?? "")
            }
            .alert("Cache Settings", isPresented: self.cacheErrorAlertBinding) {
                Button("OK", role: .cancel) {
                    self.viewModel.cacheErrorMessage = nil
                }
            } message: {
                Text(self.viewModel.cacheErrorMessage ?? "")
            }
            .alert("Google Ads", isPresented: self.adAlertBinding) {
                Button("OK") {
                    self.adPlaybackViewModel.message = nil
                }
            } message: {
                Text(self.adPlaybackViewModel.message ?? "")
            }
            .sheet(isPresented: self.$isShowingInAppPurchase) {
                InAppPurchaseSheetView(
                    applyPurchaseAction: { transaction, plan in
                        try self.viewModel.applyStoreKitPurchase(
                            transaction: transaction,
                            plan: plan
                        )
                    },
                    restorePurchasesAction: {
                        try await self.viewModel.restoreStoreKitPurchases()
                    }
                )
            }
            .onAppear {
                self.viewModel.refreshDiagnosticCode()
                CrashDiagnostics.shared.setScreen(.settings)
                AppAnalytics.shared.logScreenView(.settings)
            }
        }
    }

    private var imageCacheLimitBinding: Binding<ImageCacheLimitOption> {
        return Binding<ImageCacheLimitOption>(
            get: {
                return self.viewModel.imageCacheSettings.limit
            },
            set: { newLimit in
                self.viewModel.selectImageCacheLimit(newLimit)
            }
        )
    }

    private var cacheErrorAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.cacheErrorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.cacheErrorMessage = nil
                }
            }
        )
    }

    private var cacheStatusAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.cacheStatusMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.cacheStatusMessage = nil
                }
            }
        )
    }

    private var adAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.adPlaybackViewModel.message != nil
            },
            set: { newValue in
                if newValue == false {
                    self.adPlaybackViewModel.message = nil
                }
            }
        )
    }

    private static var versionText: String {
        let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView(viewModel: SettingsViewModel(imageCacheConfigurator: ImageCacheConfigurator()))
}
