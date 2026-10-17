import SwiftUI

struct TemporaryHistoryWebPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    /// 中文注释：网页播放器拿不到播放进度，`playback_closed` 的时长取打开到关闭。
    @State private var openedAt: Date = Date()

    let url: URL
    let title: String

    var body: some View {
        VideoWebPlayerView(
            request: VideoWebPlayerRequest(url: self.url),
            title: self.title,
            onPageLoaded: {
                AppAnalytics.shared.logPlaybackStarted(source: nil, kind: .video, playerType: .web, entry: .temporary)
            },
            onClose: {
                self.dismiss()
            }
        )
        .navigationBarBackButtonHidden(true)
        .analyticsScreen(.temporaryPlayer)
        .onAppear {
            self.openedAt = Date()
        }
        .onDisappear {
            AppAnalytics.shared.logPlaybackClosed(
                kind: .video,
                playerType: .web,
                duration: Date().timeIntervalSince(self.openedAt)
            )
        }
    }
}

struct TemporaryHistoryNativePlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    /// 中文注释：`playback_started` 每次打开只报第一次就绪。
    @State private var didReportStart: Bool = false
    /// 中文注释：临时资源不记进度，`playback_closed` 的时长取打开到关闭。
    @State private var openedAt: Date = Date()

    let mediaURL: URL
    let title: String

    var body: some View {
        VideoNativePlayerView(
            mediaURL: self.mediaURL,
            requestConfig: nil,
            title: self.title,
            onProgress: { _, _ in },
            onReadyToPlay: { _ in
                guard self.didReportStart == false else {
                    return
                }
                self.didReportStart = true
                AppAnalytics.shared.logPlaybackStarted(source: nil, kind: .video, playerType: .native, entry: .temporary)
            },
            onClose: {
                self.dismiss()
            }
        )
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .analyticsScreen(.temporaryPlayer)
        .onAppear {
            self.openedAt = Date()
        }
        .onDisappear {
            AppAnalytics.shared.logPlaybackClosed(
                kind: .video,
                playerType: .native,
                duration: Date().timeIntervalSince(self.openedAt)
            )
        }
    }
}
