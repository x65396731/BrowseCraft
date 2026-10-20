import BrowseCraftLog
import SwiftUI
import UIKit

/// 品牌等待标记（docs/design/Brand-Waiting-Mark-Design.md）：圆形墨青底板 + 海报帧 + 静音循环视频。
///
/// 中文注释：只管「在等」，没有文字、不可点；文字与是否挡点击由宿主决定，读屏只读宿主的文字。
/// 只用在用户盯着等的地方（删除账号进度遮罩、iCloud 首次恢复卡、漫画阅读器换话），按钮内与行内的小转圈不换成它。
struct BrandWaitingMark: View {
    enum Size {
        /// 96pt：删除账号进度遮罩。
        case large
        /// 56pt：iCloud 首次恢复卡（与原来的图标圈同大）、漫画阅读器换话的贴边浮层。
        case medium

        var side: CGFloat {
            switch self {
            case .large:
                return 96
            case .medium:
                return 56
            }
        }

        var fallbackControlSize: ControlSize {
            switch self {
            case .large:
                return .large
            case .medium:
                return .regular
            }
        }
    }

    struct Assets {
        let videoURL: URL?
        let posterImage: UIImage?

        init(resource: BundledWaitingAnimationResource) {
            do {
                self.videoURL = try resource.videoURL()
            } catch {
                self.videoURL = nil
                #if DEBUG
                AppLog.debug(.app, "brand-waiting-missing-video", ["message": .text("\(error.localizedDescription)")])
                #endif
            }

            self.posterImage = UIImage(named: BundledWaitingAnimationResource.posterImageName)
            if self.posterImage == nil {
                #if DEBUG
                AppLog.debug(.app, "brand-waiting-missing-poster")
                #endif
            }
        }
    }

    /// 中文注释：资源查找只做一次；各宿主共用同一份地址与海报帧。
    private static let sharedAssets: Assets = Assets(resource: BundledWaitingAnimationResource())

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isVideoReady: Bool = false
    @State private var didVideoFail: Bool = false

    let size: Size
    private let assets: Assets

    init(size: Size) {
        self.size = size
        self.assets = Self.sharedAssets
    }

    init(size: Size, assets: Assets) {
        self.size = size
        self.assets = assets
    }

    var body: some View {
        Group {
            if self.showsFallback {
                // 中文注释：素材缺失或解码失败时退回同尺寸系统转圈——静止的海报帧看不出「还在等」。
                ProgressView()
                    .controlSize(self.size.fallbackControlSize)
                    .frame(width: self.size.side, height: self.size.side)
            } else {
                self.mark
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onChange(of: self.reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                self.isVideoReady = false
            }
        }
    }

    private var mark: some View {
        ZStack {
            CatalogPalette.brandWaitingFill

            if let posterImage: UIImage = self.assets.posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFill()
            }

            // 中文注释：开了「减弱动态效果」只留海报帧（裁定 8）。前后台由播放器自己跟随 App 活跃状态暂停与续播，
            // 这里不再按 scenePhase 传——推入页回前台时 scenePhase 不一定刷新回 active。
            if self.reduceMotion == false,
               let videoURL: URL = self.assets.videoURL {
                StartupVideoPlayerView(
                    videoURL: videoURL,
                    isPlaybackActive: true,
                    isMuted: true,
                    onReady: {
                        self.isVideoReady = true
                    },
                    onFailure: {
                        self.isVideoReady = false
                        self.didVideoFail = true
                    }
                )
                .opacity(self.isVideoReady ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: self.isVideoReady)
            }
        }
        .frame(width: self.size.side, height: self.size.side)
        .clipShape(Circle())
    }

    private var showsFallback: Bool {
        if self.reduceMotion {
            return self.assets.posterImage == nil
        }
        return self.assets.videoURL == nil || self.didVideoFail
    }
}
