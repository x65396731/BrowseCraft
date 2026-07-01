import NukeUI
import SwiftUI

/// Shared cover image view.
///
/// NukeUI appears here, at the UI edge of the app. Domain and Application never
/// import NukeUI.
struct CoverImageView: View {
    let urlString: String?

    var body: some View {
        if let urlString: String = self.urlString, let url: URL = URL(string: urlString) {
            LazyImage(source: url) { state in
                if let image = state.image {
                    image
                        .resizingMode(.aspectFill)
                } else {
                    self.placeholder
                }
            }
        } else {
            self.placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))

            SwiftUI.Image(systemName: "photo")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }
}
