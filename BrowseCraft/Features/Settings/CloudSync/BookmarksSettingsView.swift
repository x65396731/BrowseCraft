import SwiftUI

struct BookmarksSettingsView: View {
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
