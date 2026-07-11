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
                                title: "Rate BrowseCraft",
                                detail: nil
                            )
                        }
                    )
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Settings")
            .alert("Rate BrowseCraft", isPresented: self.$isShowingRatingAlert) {
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
                InAppPurchaseSheetView { transaction, plan in
                    try self.viewModel.applyStoreKitPurchase(
                        transaction: transaction,
                        plan: plan
                    )
                }
            }
            .onAppear {
                self.viewModel.refreshDiagnosticCode()
                CrashDiagnostics.shared.setScreen(.settings)
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
                Label("Favorites are managed from the Favorites tab.", systemImage: "heart")
                Label("Saved bookmark folders can be added after the bookmark model is introduced.", systemImage: "folder")
            }
        }
        .navigationTitle("Bookmarks")
    }
}

private struct InAppPurchaseSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: InAppPurchaseStore

    init(
        applyPurchaseAction: @escaping @MainActor (StoreKit.Transaction, InAppPurchasePlan) async throws -> Void = { _, _ in }
    ) {
        _store = StateObject(wrappedValue: InAppPurchaseStore(applyPurchaseAction: applyPurchaseAction))
    }

    var body: some View {
        NavigationStack {
            InAppPurchasePlanSelectionView(
                store: self.store,
                closeAction: {
                    self.dismiss()
                }
            )
        }
        .alert("In-App Purchase", isPresented: self.store.statusAlertBinding) {
            Button("OK") {
                self.store.statusMessage = nil
            }
        } message: {
            Text(self.store.statusMessage ?? "")
        }
    }
}

private struct InAppPurchasePlanSelectionView: View {
    @ObservedObject var store: InAppPurchaseStore
    let closeAction: () -> Void

    private let plans: [InAppPurchasePlan] = [
        .year,
        .quarter,
        .month
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In-App Purchase")
                        .font(.largeTitle.bold())

                    Text("Choose a plan for premium access.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                VStack(spacing: 12) {
                    ForEach(self.plans) { plan in
                        Button(
                            action: {
                                Task {
                                    await self.store.purchase(plan)
                                }
                            },
                            label: {
                                InAppPurchasePlanButton(
                                    plan: plan,
                                    priceText: self.store.priceText(for: plan),
                                    isLoading: self.store.activeProductID == plan.productID
                                )
                            }
                        )
                        .buttonStyle(.plain)
                        .disabled(self.store.isLoading || self.store.activeProductID != nil)
                    }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Cloud sync across devices", systemImage: "icloud")
                    Label("Larger cache limits", systemImage: "externaldrive")
                    Label("Future AI rule assistant", systemImage: "sparkles")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if let message: String = self.store.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                }

                HStack {
                    Button(
                        action: {
                            Task {
                                await self.store.restorePurchases()
                            }
                        },
                        label: {
                            Label("Restore", systemImage: "arrow.clockwise")
                        }
                    )
                    .buttonStyle(.bordered)
                    .disabled(self.store.isLoading || self.store.activeProductID != nil)

                    Spacer()

                    NavigationLink(destination: MoreInAppPurchasePlansView(store: self.store, closeAction: self.closeAction)) {
                        Label("More Plans", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("In-App Purchase")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await self.store.loadProducts()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(
                    action: self.closeAction,
                    label: {
                        Image(systemName: "xmark")
                    }
                )
                .accessibilityLabel("Close")
            }
        }
    }
}

private struct MoreInAppPurchasePlansView: View {
    @ObservedObject var store: InAppPurchaseStore
    let closeAction: () -> Void

    private let plans: [InAppPurchasePlan] = [
        .siteSlot1,
        .siteSlot5,
        .siteSlot10,
        .siteSlot30
    ]

    var body: some View {
        List {
            ForEach(self.plans) { plan in
                Button(
                    action: {
                        Task {
                            await self.store.purchase(plan)
                        }
                    },
                    label: {
                        HStack(spacing: 12) {
                            Image(systemName: plan.systemImage)
                                .foregroundColor(.accentColor)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.title)
                                Text(plan.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if self.store.activeProductID == plan.productID {
                                ProgressView()
                            } else {
                                Text(self.store.priceText(for: plan))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                )
                .buttonStyle(.plain)
                .disabled(self.store.isLoading || self.store.activeProductID != nil)
                .padding(.vertical, 4)
            }

            Section {
                Button(
                    action: {
                        Task {
                            await self.store.purchase(.removeAds)
                        }
                    },
                    label: {
                        HStack(spacing: 12) {
                            Image(systemName: InAppPurchasePlan.removeAds.systemImage)
                                .foregroundColor(.accentColor)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(InAppPurchasePlan.removeAds.title)
                                Text(InAppPurchasePlan.removeAds.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if self.store.activeProductID == InAppPurchasePlan.removeAds.productID {
                                ProgressView()
                            } else {
                                Text(self.store.priceText(for: .removeAds))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                )
                .buttonStyle(.plain)
                .disabled(self.store.isLoading || self.store.activeProductID != nil)
            }
        }
        .navigationTitle("More Plans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(
                    action: self.closeAction,
                    label: {
                        Image(systemName: "xmark")
                    }
                )
                .accessibilityLabel("Close")
            }
        }
    }
}

private struct InAppPurchasePlanButton: View {
    let plan: InAppPurchasePlan
    let priceText: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: self.plan.systemImage)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.plan.title)
                    .font(.headline)

                Text(self.plan.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            if self.isLoading {
                ProgressView()
            } else {
                Text(self.priceText)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct InAppPurchasePlan: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let productID: String
    let fallbackPrice: String
    let siteSlotIncrement: Int
    let vipMonthDuration: Int
    let removesAds: Bool

    var id: String {
        return self.productID
    }

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        productID: String,
        fallbackPrice: String,
        siteSlotIncrement: Int = 0,
        vipMonthDuration: Int = 0,
        removesAds: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.productID = productID
        self.fallbackPrice = fallbackPrice
        self.siteSlotIncrement = siteSlotIncrement
        self.vipMonthDuration = vipMonthDuration
        self.removesAds = removesAds
    }

    static let year: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Year",
        subtitle: "Best value for full access",
        systemImage: "calendar.badge.clock",
        productID: "browsecraft.premium.year",
        fallbackPrice: "$19.99",
        vipMonthDuration: 12
    )

    static let quarter: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Quarter",
        subtitle: "Flexible seasonal access",
        systemImage: "calendar",
        productID: "browsecraft.premium.quarter",
        fallbackPrice: "$6.99",
        vipMonthDuration: 3
    )

    static let month: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Month",
        subtitle: "Try premium features first",
        systemImage: "calendar.badge.plus",
        productID: "browsecraft.premium.month",
        fallbackPrice: "$2.99",
        vipMonthDuration: 1
    )

    static let siteSlot1: InAppPurchasePlan = InAppPurchasePlan(
        title: "1 Site Slot",
        subtitle: "Add one custom site position",
        systemImage: "square.grid.2x2",
        productID: "browsecraft.site.slot.1",
        fallbackPrice: "$0.99",
        siteSlotIncrement: 1
    )

    static let siteSlot5: InAppPurchasePlan = InAppPurchasePlan(
        title: "5 Site Slots",
        subtitle: "Add five custom site positions",
        systemImage: "square.grid.3x2",
        productID: "browsecraft.site.slot.5",
        fallbackPrice: "$3.99",
        siteSlotIncrement: 5
    )

    static let siteSlot10: InAppPurchasePlan = InAppPurchasePlan(
        title: "10 Site Slots",
        subtitle: "Add ten custom site positions",
        systemImage: "square.grid.3x3",
        productID: "browsecraft.site.slot.10",
        fallbackPrice: "$6.99",
        siteSlotIncrement: 10
    )

    static let siteSlot30: InAppPurchasePlan = InAppPurchasePlan(
        title: "30 Site Slots",
        subtitle: "Add thirty custom site positions",
        systemImage: "rectangle.grid.3x2",
        productID: "browsecraft.site.slot.30",
        fallbackPrice: "$14.99",
        siteSlotIncrement: 30
    )

    static let removeAds: InAppPurchasePlan = InAppPurchasePlan(
        title: "Remove Ads",
        subtitle: "Hide rewarded ad prompts permanently",
        systemImage: "nosign",
        productID: "browsecraft.remove.ads",
        fallbackPrice: "$4.99",
        removesAds: true
    )

    static let allPlans: [InAppPurchasePlan] = [
        .year,
        .quarter,
        .month,
        .siteSlot1,
        .siteSlot5,
        .siteSlot10,
        .siteSlot30,
        .removeAds
    ]
}

@MainActor
private final class InAppPurchaseStore: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var productsByID: [String: Product] = [:]
    @Published var statusMessage: String?

    private let applyPurchaseAction: @MainActor (StoreKit.Transaction, InAppPurchasePlan) async throws -> Void

    init(
        applyPurchaseAction: @escaping @MainActor (StoreKit.Transaction, InAppPurchasePlan) async throws -> Void = { _, _ in }
    ) {
        self.applyPurchaseAction = applyPurchaseAction
    }

    func loadProducts() async {
        guard self.productsByID.isEmpty else {
            return
        }

        self.isLoading = true
        self.statusMessage = nil
        defer {
            self.isLoading = false
        }

        do {
            let productIDs: [String] = InAppPurchasePlan.allPlans.map(\.productID)
            let products: [Product] = try await Product.products(for: productIDs)
            self.productsByID = Dictionary(uniqueKeysWithValues: products.map { product in
                return (product.id, product)
            })

            if products.isEmpty {
                self.statusMessage = "No StoreKit products were found. Add matching product IDs in a StoreKit configuration file for local testing."
            }
        } catch {
            self.statusMessage = "Products could not be loaded."
        }
    }

    func priceText(for plan: InAppPurchasePlan) -> String {
        return self.productsByID[plan.productID]?.displayPrice ?? plan.fallbackPrice
    }

    func purchase(_ plan: InAppPurchasePlan) async {
        guard self.activeProductID == nil else {
            return
        }

        self.activeProductID = plan.productID
        self.statusMessage = nil
        defer {
            self.activeProductID = nil
        }

        if self.productsByID.isEmpty {
            await self.loadProducts()
        }

        guard let product: Product = self.productsByID[plan.productID] else {
            self.statusMessage = "Product not available. Run the app from Xcode with the BrowseCraft scheme so BrowseCraft.storekit is injected."
            return
        }

        do {
            let result: Product.PurchaseResult = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction: StoreKit.Transaction = try self.verifiedTransaction(from: verification)
                try await self.applyPurchaseAction(transaction, plan)
                await transaction.finish()
                self.statusMessage = "\(plan.title) purchase completed."
            case .pending:
                self.statusMessage = "\(plan.title) purchase is pending."
            case .userCancelled:
                self.statusMessage = "Purchase cancelled."
            @unknown default:
                self.statusMessage = "Purchase ended with an unknown result."
            }
        } catch {
            self.statusMessage = "Purchase failed."
        }
    }

    func restorePurchases() async {
        self.isLoading = true
        self.statusMessage = nil
        defer {
            self.isLoading = false
        }

        do {
            try await AppStore.sync()
            self.statusMessage = "Purchases restored."
        } catch {
            self.statusMessage = "Purchases could not be restored."
        }
    }

    private func verifiedTransaction(
        from result: VerificationResult<StoreKit.Transaction>
    ) throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw StoreKitVerificationError.unverifiedTransaction
        }
    }

    var statusAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.statusMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.statusMessage = nil
                }
            }
        )
    }
}

private enum StoreKitVerificationError: Error {
    case unverifiedTransaction
}

private struct CacheSettingsView: View {
    @Binding var selectedImageCacheLimit: ImageCacheLimitOption
    let clearCacheAction: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Image Cache Limit", selection: self.$selectedImageCacheLimit) {
                    ForEach(ImageCacheSettings.availableLimits) { option in
                        Text(option.displayTitle)
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("When the cache exceeds the selected limit, older image cache will be removed automatically. Recently used images are kept first.")
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
    SettingsView(viewModel: SettingsViewModel(imageCacheConfigurator: ImageCacheConfigurator()))
}
