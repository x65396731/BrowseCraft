import SwiftUI

struct CacheSettingsView: View {
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
