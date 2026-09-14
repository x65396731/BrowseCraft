import ReadiumNavigator
import SwiftUI

// 中文注释：有声作品播放页——照抄 Readium TestApp 的 AudiobookReader（封面、进度条、快退 10 秒 / 上一章 / 播放暂停 / 下一章 / 快进 30 秒），
// 只换成本项目的 ViewModel；样式后续再改。播放内核是 AudioNavigator，本视图不持有任何播放状态。

struct AudiobookPlayerView: View {
    let viewModel: BookReaderViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if let coverURL: URL = self.viewModel.coverURL {
                // 中文注释：同 BookSiteDetailView——共享 CoverImageView 负责 http → https，系统 AsyncImage 直连会被 ATS 拒。
                CoverImageView(urlString: coverURL.absoluteString)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "headphones").font(.system(size: 64)).foregroundStyle(.secondary)
            }
            if let chapterTitle: String = self.viewModel.audioChapterTitle {
                Text(chapterTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if let navigator: AudioNavigator = self.viewModel.audioNavigator {
                if self.viewModel.audioPlayback.state == .loading {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    if let duration: Double = self.viewModel.audioPlayback.duration, duration > 0 {
                        AudiobookTimeSlider(
                            time: Binding(
                                get: { self.viewModel.audioPlayback.time },
                                set: { value in
                                    Task { await navigator.seek(to: value) }
                                }
                            ),
                            duration: duration
                        )
                    }
                    HStack(spacing: 24) {
                        Spacer()
                        self.iconButton("gobackward.10") { Task { await navigator.seek(by: -10) } }
                        self.iconButton("backward.fill") { Task { await navigator.goBackward() } }
                            .disabled(navigator.canGoBackward == false)
                        self.iconButton(self.viewModel.audioPlayback.state != .paused ? "pause.fill" : "play.fill") {
                            navigator.playPause()
                        }
                        self.iconButton("forward.fill") { Task { await navigator.goForward() } }
                            .disabled(navigator.canGoForward == false)
                        self.iconButton("goforward.30") { Task { await navigator.seek(by: 30) } }
                        Spacer()
                    }
                }
            }
            Spacer()
        }
        .padding(32)
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        return Button(action: action) {
            Image(systemName: systemName).font(.title)
        }
    }
}

/// 中文注释：拖动时不让播放进度回写滑块；松手才 seek（照抄 TestApp 的 TimeSlider）。
struct AudiobookTimeSlider: View {
    @Binding var time: Double
    let duration: Double
    @State private var isEditing: Bool = false
    @State private var progress: Double = 0

    var body: some View {
        Slider(
            value: self.$progress,
            label: { EmptyView() },
            minimumValueLabel: { Text(Self.format(self.time)) },
            maximumValueLabel: { Text(Self.format(self.duration)) },
            onEditingChanged: { isEditing in
                self.isEditing = isEditing
                if isEditing == false {
                    self.time = self.progress * self.duration
                }
            }
        )
        .onChange(of: self.time) {
            if self.isEditing == false {
                self.progress = self.time / self.duration
            }
        }
        .onAppear {
            self.progress = self.duration > 0 ? self.time / self.duration : 0
        }
    }

    static func format(_ time: Double) -> String {
        let formatter: DateComponentsFormatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = time > 60 * 60 ? [.hour, .minute, .second] : [.minute, .second]
        return formatter.string(from: time) ?? "00:00"
    }
}
