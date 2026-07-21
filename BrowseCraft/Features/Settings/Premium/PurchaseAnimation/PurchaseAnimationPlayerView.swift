import SwiftUI
import UIKit

struct PurchaseAnimationPlayerView: View {
    struct Assets {
        let videoURL: URL?
        let posterImage: UIImage?

        init(resource: BundledPurchaseAnimationResource) {
            do {
                self.videoURL = try resource.videoURL()
            } catch {
                self.videoURL = nil
                Self.logMissingResource(kind: "video", error: error)
            }

            do {
                let posterURL: URL = try resource.posterURL()
                self.posterImage = UIImage(contentsOfFile: posterURL.path)
                if self.posterImage == nil {
                    Self.logMissingResource(kind: "poster image data", error: nil)
                }
            } catch {
                self.posterImage = nil
                Self.logMissingResource(kind: "poster", error: error)
            }
        }

        private static func logMissingResource(kind: String, error: Error?) {
            #if DEBUG
            let detail: String = error?.localizedDescription ?? "the image data could not be decoded"
            print("[BrowseCraftPurchaseAnimation] missing \(kind): \(detail)")
            #endif
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var isVideoReady: Bool = false

    private let assets: Assets
    private let isPlaybackEnabled: Bool

    init(
        resource: BundledPurchaseAnimationResource = BundledPurchaseAnimationResource(),
        isPlaybackEnabled: Bool = true
    ) {
        self.assets = Assets(resource: resource)
        self.isPlaybackEnabled = isPlaybackEnabled
    }

    init(assets: Assets, isPlaybackEnabled: Bool) {
        self.assets = assets
        self.isPlaybackEnabled = isPlaybackEnabled
    }

    var body: some View {
        ZStack {
            Color.black

            if let posterImage: UIImage = self.assets.posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFill()
            }

            if self.reduceMotion == false,
               let videoURL: URL = self.assets.videoURL {
                PurchaseAnimationKSPlayerView(
                    videoURL: videoURL,
                    isPlaybackActive: self.scenePhase == .active && self.isPlaybackEnabled,
                    onReady: {
                        self.isVideoReady = true
                    },
                    onFailure: {
                        self.isVideoReady = false
                    }
                )
                .opacity(self.isVideoReady ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: self.isVideoReady)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.48)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onChange(of: self.reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                self.isVideoReady = false
            }
        }
    }
}
