import BrowseCraftDomain
import Nuke
@preconcurrency import ReadiumNavigator
import SwiftUI
import UIKit

// 中文注释：有声书播放页（docs/design/Audiobook-Player-Page-Redesign-Design.md）。播放内核是 `AudiobookPlaybackEngine`（Readium `AudioNavigator`，
// HLS 音频为 `SiteHLSAudioPlayer`），// 本视图不持有播放状态；界面全是自绘：沉浸深色 + 封面取色流动背景、毛玻璃返回与目录、方形封面、眉行「第 N / M 集」、
// 集名与书名、进度条、五键主控件、倍速胶囊。单集取不到时进度条位置换成一行横条（fwq `APP-MEMO-043`）。
// 整页深色只对本页局部设（`.environment(\.colorScheme, .dark)`），不用 `preferredColorScheme`——推入页上用它会把整个窗口一起变深。

struct AudiobookPlayerView: View {
    let viewModel: BookReaderViewModel
    let backAction: () -> Void

    @Environment(\.browserRequestHeaderProvider) private var browserRequestHeaderProvider
    @Environment(\.systemCookieHeaderProvider) private var systemCookieHeaderProvider
    @State private var isContentsPresented: Bool = false
    @State private var coverImage: UIImage?
    @State private var palette: AudiobookBackdropPalette = .book

    private static let coverMaxSide: CGFloat = 300

    var body: some View {
        GeometryReader { geometry in
            let coverSide: CGFloat = Self.coverSide(for: geometry.size)
            VStack(spacing: 0) {
                AudiobookTopBar(
                    backAction: self.backAction,
                    contentsAction: { self.isContentsPresented = true },
                    isContentsEnabled: self.viewModel.audioChapterCount > 0
                )
                Spacer(minLength: 8)
                self.cover(side: coverSide)
                self.titles
                    .padding(.top, 28)
                Group {
                    if let failure: BookAudioResourceFailure.Kind = self.viewModel.currentAudioChapterFailure {
                        AudiobookFailureStrip(
                            kind: failure,
                            canGoNext: self.viewModel.canGoToNextAudioChapter,
                            nextInk: self.palette.base,
                            retryAction: { Task { await self.viewModel.retryCurrentAudioChapter() } },
                            nextAction: { Task { await self.viewModel.playNextAudioChapter() } }
                        )
                    } else {
                        AudiobookProgressBar(
                            time: self.viewModel.displayedAudioPlayback.time,
                            duration: self.viewModel.displayedAudioPlayback.duration,
                            isEnabled: self.isSeekable,
                            seekAction: { time in
                                Task { await self.viewModel.audioEngine?.seek(to: time) }
                            }
                        )
                    }
                }
                .padding(.top, 22)
                self.controls
                    .padding(.top, 22)
                AudiobookSpeedMenu(
                    speed: self.viewModel.playbackSpeed,
                    selectAction: { speed in self.viewModel.setPlaybackSpeed(speed) }
                )
                .padding(.top, 26)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background {
            AudiobookFlowingBackdrop(palette: self.palette)
        }
        .foregroundStyle(CatalogPalette.immersiveText)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: self.$isContentsPresented) {
            AudiobookContentsSheet(
                viewModel: self.viewModel,
                dismissAction: { self.isContentsPresented = false }
            )
            .environment(\.colorScheme, .dark)
        }
        .task(id: self.viewModel.coverURL) {
            await self.loadCover()
        }
    }

    private var isPlaying: Bool {
        return self.viewModel.displayedAudioPlayback.state == .playing
    }

    private var isLoading: Bool {
        return self.viewModel.displayedAudioPlayback.state == .loading
    }

    private var isFailed: Bool {
        return self.viewModel.currentAudioChapterFailure != nil
    }

    private var isSeekable: Bool {
        guard let duration: Double = self.viewModel.displayedAudioPlayback.duration else {
            return false
        }
        return duration > 0 && self.isLoading == false
    }

    /// 中文注释：封面边长 = min(屏宽 − 96, 300)；矮屏再缩，保证倍速胶囊不被压出屏（第四节「对齐」）。
    private static func coverSide(for size: CGSize) -> CGFloat {
        let byWidth: CGFloat = min(size.width - 96, Self.coverMaxSide)
        let byHeight: CGFloat = max(160, size.height - 430)
        return max(0, min(byWidth, byHeight))
    }

    // MARK: 封面

    @ViewBuilder
    private func cover(side: CGFloat) -> some View {
        Group {
            if let coverImage: UIImage = self.coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
            } else {
                // 中文注释：无封面（中文三站都不给）与加载中：书籍深色色块 + 耳机（裁定 3）。
                ZStack {
                    CatalogKindStyle.of(.book).bannerBackground
                    Image(systemName: "headphones")
                        .font(.system(size: side * 0.24, weight: .regular))
                        .foregroundStyle(CatalogKindStyle.of(.book).bannerAccent)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: CatalogPalette.posterShadow, radius: 20, y: 10)
        .accessibilityHidden(true)
    }

    // MARK: 标题区

    private var titles: some View {
        VStack(spacing: 6) {
            if let eyebrow: String = self.eyebrow {
                HStack(spacing: 6) {
                    if self.isPlaying {
                        AudiobookWaveformGlyph()
                    }
                    Text(eyebrow)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(CatalogPalette.immersiveEyebrow)
            }
            Text(self.chapterTitle)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(self.viewModel.title)
                .font(.subheadline)
                .foregroundStyle(CatalogPalette.immersiveSecondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// 中文注释：听完最后一集写「全部听完了」；只有一集时不出眉行。
    private var eyebrow: String? {
        if self.viewModel.didFinishAudiobook {
            return NSLocalizedString("audiobook_player_finished", comment: "有声书：最后一集播完")
        }
        guard self.viewModel.audioChapterCount > 1 else {
            return nil
        }
        return String(
            format: NSLocalizedString("audiobook_player_episode_position", comment: "有声书眉行：第 N / M 集"),
            self.viewModel.audioChapterIndex + 1,
            self.viewModel.audioChapterCount
        )
    }

    private var chapterTitle: String {
        if let title: String = self.viewModel.audioChapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines), title.isEmpty == false {
            return title
        }
        return String(
            format: NSLocalizedString("audiobook_player_episode_fallback", comment: "有声书：集名缺时写第 N 集"),
            self.viewModel.audioChapterIndex + 1
        )
    }

    // MARK: 主控件

    private var controls: some View {
        HStack {
            AudiobookControlButton(
                systemImage: "gobackward.10",
                size: 28,
                label: NSLocalizedString("audiobook_player_skip_back", comment: "读屏：后退 10 秒"),
                isEnabled: self.isFailed == false
            ) {
                Task { await self.viewModel.audioEngine?.seek(by: -10) }
            }
            Spacer(minLength: 0)
            AudiobookControlButton(
                systemImage: "backward.end.fill",
                size: 24,
                label: NSLocalizedString("audiobook_player_previous", comment: "读屏：上一集"),
                isEnabled: self.viewModel.canGoToPreviousAudioChapter
            ) {
                Task { await self.viewModel.playPreviousAudioChapter() }
            }
            Spacer(minLength: 0)
            self.playButton
            Spacer(minLength: 0)
            AudiobookControlButton(
                systemImage: "forward.end.fill",
                size: 24,
                label: NSLocalizedString("audiobook_player_next", comment: "读屏：下一集"),
                isEnabled: self.viewModel.canGoToNextAudioChapter
            ) {
                Task { await self.viewModel.playNextAudioChapter() }
            }
            Spacer(minLength: 0)
            AudiobookControlButton(
                systemImage: "goforward.30",
                size: 28,
                label: NSLocalizedString("audiobook_player_skip_forward", comment: "读屏：前进 30 秒"),
                isEnabled: self.isFailed == false
            ) {
                Task { await self.viewModel.audioEngine?.seek(by: 30) }
            }
        }
        .padding(.horizontal, 6)
    }

    /// 中文注释：72pt 白色实心圆、图形取背景底色（青绿在不同封面色上会撞色）；单集失败时变灰不可点；加载中圆内转圈、仍可点。
    private var playButton: some View {
        Button {
            self.viewModel.audioEngine?.playPause()
        } label: {
            ZStack {
                Circle()
                    .fill(self.isFailed ? CatalogPalette.immersiveStroke : CatalogPalette.immersiveText)
                if self.isLoading && self.isFailed == false {
                    ProgressView()
                        .tint(self.palette.base)
                } else {
                    Image(systemName: self.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(self.isFailed ? CatalogPalette.immersiveSecondaryText : self.palette.base)
                        .offset(x: self.isPlaying ? 0 : 2)
                }
            }
            .frame(width: 72, height: 72)
            .shadow(color: self.isFailed ? SwiftUI.Color.clear : CatalogPalette.posterShadow, radius: 12, y: 8)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(self.isFailed)
        .accessibilityLabel(
            self.isPlaying
                ? NSLocalizedString("audiobook_player_pause", comment: "读屏：暂停")
                : NSLocalizedString("audiobook_player_play", comment: "读屏：播放")
        )
    }

    // MARK: 封面图

    /// 中文注释：与 `CoverImageView` 同一条请求链（http → https、请求头、Cookie），多要一份 `UIImage` 给取色与锁屏封面。
    private func loadCover() async {
        self.coverImage = nil
        self.palette = .book
        guard let coverURL: URL = self.viewModel.coverURL,
              let identity: RemoteImageRequestIdentity = RemoteImageRequestIdentity(
                urlString: coverURL.absoluteString,
                refererURLString: nil,
                requestConfig: nil,
                additionalHeaders: nil,
                displaySize: CGSize(width: Self.coverMaxSide, height: Self.coverMaxSide)
              ),
              let request: ImageRequest = RemoteImageRequestBuilder.makeRequest(
                identity,
                browserRequestHeaderProvider: self.browserRequestHeaderProvider,
                systemCookieHeaderProvider: self.systemCookieHeaderProvider,
                diagnosticViewID: "audiobook-player"
              ) else {
            return
        }
        do {
            let image: UIImage = try await ImagePipeline.shared.image(for: request)
            guard Task.isCancelled == false else {
                return
            }
            self.coverImage = image
            self.palette = AudiobookBackdropPalette(image: image) ?? .book
            self.viewModel.setAudioArtwork(image)
        } catch {
            // 中文注释：取不到封面就留在无封面的样子（青绿深调 + 耳机），失败照常记一条（`BCA-OBS-016`）。
            ImageRequestFactory.logFailure(urlString: coverURL.absoluteString, error: error, event: "audiobook-cover-failure")
        }
    }
}

// MARK: - 打开中

/// 中文注释：整站有声的作品打开中：同一张深色流动背景上的同形骨架（白 10–12%），只有返回可点；加载完不跳动（第六节）。
struct AudiobookLoadingView: View {
    let backAction: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let side: CGFloat = max(0, min(geometry.size.width - 96, 300, max(160, geometry.size.height - 430)))
            VStack(spacing: 0) {
                AudiobookTopBar(backAction: self.backAction, contentsAction: {}, isContentsEnabled: false)
                Spacer(minLength: 8)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CatalogPalette.onDarkFill)
                    .frame(width: side, height: side)
                VStack(spacing: 10) {
                    Capsule().fill(CatalogPalette.onDarkFill).frame(width: 64, height: 10)
                    Capsule().fill(CatalogPalette.onDarkFill).frame(width: 200, height: 18)
                    Capsule().fill(CatalogPalette.onDarkFill).frame(width: 140, height: 13)
                }
                .padding(.top, 28)
                Capsule()
                    .fill(CatalogPalette.immersiveTrack)
                    .frame(height: 4)
                    .frame(height: 44)
                    .padding(.top, 22)
                Circle()
                    .fill(CatalogPalette.onDarkFill)
                    .frame(width: 72, height: 72)
                    .padding(.top, 36)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background {
            AudiobookFlowingBackdrop(palette: .book)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 顶栏

/// 中文注释：左返回、右目录：40pt 毛玻璃圆 + 白 16% 描边，热区 44；做法照 `DetailTopButtons`，底换成毛玻璃。
private struct AudiobookTopBar: View {
    let backAction: () -> Void
    let contentsAction: () -> Void
    let isContentsEnabled: Bool

    var body: some View {
        HStack {
            self.circle(systemImage: "chevron.left", label: NSLocalizedString("Back", comment: ""), action: self.backAction)
            Spacer(minLength: 0)
            self.circle(systemImage: "list.bullet", label: NSLocalizedString("Contents", comment: "目录"), action: self.contentsAction)
                .disabled(self.isContentsEnabled == false)
                .opacity(self.isContentsEnabled ? 1 : 0.45)
        }
        .padding(.top, 8)
    }

    private func circle(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        return Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(CatalogPalette.immersiveText)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(CatalogPalette.immersiveStroke, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 主控件的小按钮

private struct AudiobookControlButton: View {
    let systemImage: String
    let size: CGFloat
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: self.size, weight: .regular))
                .foregroundStyle(CatalogPalette.immersiveText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(self.isEnabled == false)
        .opacity(self.isEnabled ? 1 : 0.35)
        .accessibilityLabel(self.label)
    }
}

// MARK: - 眉行波形

/// 中文注释：播放中眉行前三根跳动的短竖条；减弱动态效果时静止。
private struct AudiobookWaveformGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var isAnimating: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .frame(width: 2, height: 10)
                    .scaleEffect(y: self.isAnimating ? 1 : 0.45, anchor: .center)
                    .animation(
                        self.isAnimating
                            ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(index) * 0.15)
                            : .default,
                        value: self.isAnimating
                    )
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
        .onAppear {
            self.isAnimating = self.reduceMotion == false
        }
    }
}

// MARK: - 进度条

/// 中文注释：自绘：4pt 轨道（白 22%）、已听部分与滑块白；滑块 14，按住 22；热区高 44。拖动时左侧显示目标时刻，松手才 seek。
/// 读屏是可调节元素：上滑前进 30 秒、下滑后退 10 秒（与主控件同步长）。
struct AudiobookProgressBar: View {
    let time: Double
    let duration: Double?
    let isEnabled: Bool
    let seekAction: (Double) -> Void

    @State private var dragFraction: Double?
    @State private var isDragging: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let width: CGFloat = geometry.size.width
                let fraction: Double = self.dragFraction ?? self.playedFraction
                let knob: CGFloat = self.isDragging ? 22 : 14
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CatalogPalette.immersiveTrack)
                        .frame(height: 4)
                    Capsule()
                        .fill(CatalogPalette.immersiveText)
                        .frame(width: width * CGFloat(fraction), height: 4)
                    if self.isEnabled {
                        Circle()
                            .fill(CatalogPalette.immersiveText)
                            .frame(width: knob, height: knob)
                            .shadow(color: CatalogPalette.cardShadow, radius: 2, y: 1)
                            .offset(x: width * CGFloat(fraction) - knob / 2)
                    }
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard self.isEnabled, width > 0 else {
                                return
                            }
                            self.isDragging = true
                            self.dragFraction = min(max(Double(value.location.x / width), 0), 1)
                        }
                        .onEnded { value in
                            guard self.isEnabled, width > 0, let duration: Double = self.duration else {
                                return
                            }
                            let target: Double = min(max(Double(value.location.x / width), 0), 1)
                            self.dragFraction = target
                            self.isDragging = false
                            self.seekAction(target * duration)
                        }
                )
                .animation(.easeOut(duration: 0.15), value: self.isDragging)
            }
            .frame(height: 44)
            HStack {
                Text(AudiobookTimeFormatter.string(self.displayedTime))
                Spacer(minLength: 0)
                Text(self.duration.map(AudiobookTimeFormatter.string) ?? AudiobookTimeFormatter.unknown)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(CatalogPalette.immersiveSecondaryText)
            .padding(.top, -8)
        }
        .onChange(of: self.time) {
            // 中文注释：松手后先停在目标位置，等引擎报来新的时间再跟回去，不闪回旧位置。
            if self.isDragging == false {
                self.dragFraction = nil
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("audiobook_player_progress", comment: "读屏：播放进度"))
        .accessibilityValue(self.accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard self.isEnabled, let duration: Double = self.duration else {
                return
            }
            switch direction {
            case .increment:
                self.seekAction(min(self.time + 30, duration))
            case .decrement:
                self.seekAction(max(self.time - 10, 0))
            @unknown default:
                break
            }
        }
    }

    private var playedFraction: Double {
        guard let duration: Double = self.duration, duration > 0 else {
            return 0
        }
        return min(max(self.time / duration, 0), 1)
    }

    private var displayedTime: Double {
        guard let dragFraction: Double = self.dragFraction, let duration: Double = self.duration else {
            return self.time
        }
        return dragFraction * duration
    }

    private var accessibilityValue: String {
        let total: String = self.duration.map(AudiobookTimeFormatter.string) ?? AudiobookTimeFormatter.unknown
        return "\(AudiobookTimeFormatter.string(self.time)) / \(total)"
    }
}

/// 中文注释：一小时以内「mm:ss」，超过「h:mm:ss」；时长未知写「--:--」。
enum AudiobookTimeFormatter {
    static let unknown: String = "--:--"

    static func string(_ time: Double) -> String {
        let formatter: DateComponentsFormatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = time >= 60 * 60 ? [.hour, .minute, .second] : [.minute, .second]
        return formatter.string(from: max(0, time)) ?? "00:00"
    }
}

// MARK: - 单集失败横条

/// 中文注释：单集取不到时替换进度条（第六节，`APP-MEMO-043`）：毛玻璃 + 警示橙描边；已失效只给「下一集」，没加载出来多一个「重试」；
/// 最后一集没有「下一集」。封面不缩、不自动跳（裁定 9）。
struct AudiobookFailureStrip: View {
    let kind: BookAudioResourceFailure.Kind
    let canGoNext: Bool
    /// 白色「下一集」上的字取背景底色，与播放键图形同一个。
    let nextInk: SwiftUI.Color
    let retryAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(CatalogPalette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CatalogPalette.immersiveText)
                Text(self.message)
                    .font(.caption)
                    .foregroundStyle(CatalogPalette.immersiveSecondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if self.kind == .unavailable {
                Button(action: self.retryAction) {
                    Text(NSLocalizedString("Retry", comment: "重试"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatalogPalette.immersiveText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(CatalogPalette.onDarkFill, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if self.canGoNext {
                Button(action: self.nextAction) {
                    HStack(spacing: 2) {
                        Text(NSLocalizedString("audiobook_player_next", comment: "下一集"))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(self.nextInk)
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                    .frame(minHeight: 36)
                    .background(CatalogPalette.immersiveText, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CatalogPalette.warning.opacity(0.45), lineWidth: 1)
        )
    }

    private var title: String {
        switch self.kind {
        case .gone:
            return NSLocalizedString("audiobook_player_gone_title", comment: "单集音频在站点上已失效")
        case .unavailable:
            return NSLocalizedString("audiobook_player_unavailable_title", comment: "单集没加载出来")
        }
    }

    private var message: String {
        switch self.kind {
        case .gone:
            return NSLocalizedString("audiobook_player_gone_message", comment: "已失效的说明")
        case .unavailable:
            return NSLocalizedString("audiobook_player_unavailable_message", comment: "没加载出来的说明")
        }
    }
}

// MARK: - 倍速

/// 中文注释：44 高毛玻璃胶囊，点开是系统菜单「播放速度」五档（裁定 6）；不是 1.0× 时字变书籍青绿。
private struct AudiobookSpeedMenu: View {
    let speed: AudiobookPlaybackSpeed
    let selectAction: (AudiobookPlaybackSpeed) -> Void

    var body: some View {
        Menu {
            Section(NSLocalizedString("audiobook_player_speed_title", comment: "倍速菜单标题")) {
                ForEach(AudiobookPlaybackSpeed.allCases) { option in
                    Button {
                        self.selectAction(option)
                    } label: {
                        if option == self.speed {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                Text(self.speed.label)
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(self.speed == .normal ? CatalogPalette.immersiveText : CatalogKindStyle.of(.book).accent)
            .padding(.horizontal, 20)
            .frame(minWidth: 88, minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(CatalogPalette.immersiveStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel(
            String(format: NSLocalizedString("audiobook_player_speed_label", comment: "读屏：播放速度 %@"), self.speed.label)
        )
    }
}
