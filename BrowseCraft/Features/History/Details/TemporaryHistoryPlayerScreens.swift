import SwiftUI

struct TemporaryHistoryWebPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL
    let title: String

    var body: some View {
        VideoWebPlayerView(
            request: VideoWebPlayerRequest(url: self.url),
            title: self.title,
            controls: {
                EmptyView()
            },
            onClose: {
                self.dismiss()
            }
        )
        .navigationBarBackButtonHidden(true)
    }
}

struct TemporaryHistoryNativePlayerScreen: View {
    @Environment(\.dismiss) private var dismiss

    let mediaURL: URL
    let title: String

    var body: some View {
        VideoNativePlayerView(
            mediaURL: self.mediaURL,
            requestConfig: nil,
            title: self.title,
            controls: {
                EmptyView()
            },
            onProgress: { _, _ in },
            onReadyToPlay: { _ in },
            onClose: {
                self.dismiss()
            }
        )
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
    }
}
