import SwiftUI
import UIKit

// 中文注释：有声书播放页的沉浸背景（docs/design/Audiobook-Player-Page-Redesign-Design.md 第四节，用户 2026-10-20 看画布后定，
// 10-24 看预览视频与真机读数后改成 MeshGradient 流体）：从封面取 3 个主色，一个压暗做底、三个在 3×3 网格里轮换并流动；
// 没有封面时用书籍青绿深调。性能约束（同节）：网格每秒最多重绘 30 帧，回到后台停；开了低电量模式或「减弱动态效果」时
// 退回三团径向渐变色块漂移（只改位移与缩放，交给 Core Animation 合成，减弱动态效果时停住）。
// 取色只在拿到封面时做一次（缩到 24×24）。不播视频、不碰音频会话。

/// 背景的四个颜色：底色与三团色块。
struct AudiobookBackdropPalette: Equatable {
    let base: Color
    let blobs: [Color]

    /// 没有封面（或取色失败）时：书籍青绿深调，与 `CatalogKindStyle.of(.book)` 的固定深色色块同一族。
    static let book: AudiobookBackdropPalette = AudiobookBackdropPalette(
        base: CatalogPalette.fixed(0x07120F),
        blobs: [CatalogPalette.fixed(0x1E7D68), CatalogPalette.fixed(0x152A26), CatalogPalette.fixed(0x2F8F7A)]
    )

    /// 中文注释：从封面取色。取不到（图太小、全透明）时返回 nil，调用方退回 `book`。
    init?(image: UIImage) {
        guard let colors: [AudiobookCoverColor] = AudiobookCoverColor.dominantColors(of: image), colors.isEmpty == false else {
            return nil
        }
        // 中文注释：底色取占比最大的一簇；三团色块取最鲜艳的三簇并提饱和度（2026-10-20 模拟器走查：按占比取，
        // Tom Sawyer 封面的天空、白栅栏与衣服被平均成一片灰，色块看不出来；10-24 真机仍偏灰，改 8 簇 + 饱和度下限 0.45）。
        // 灰色簇（饱和度很低）不提，免得凭空染色。
        let primary: AudiobookCoverColor = colors[0]
        self.base = primary.adjusted(saturationCap: 0.55, brightness: 0.11).color
        let vivid: [AudiobookCoverColor] = colors.sorted { $0.vividness > $1.vividness }
        self.blobs = (0..<3).map { index in
            let color: AudiobookCoverColor = vivid[min(index, vivid.count - 1)]
            return color.boosted().adjusted(saturationCap: 0.65, brightnessRange: 0.38...0.62).color
        }
    }

    init(base: Color, blobs: [Color]) {
        self.base = base
        self.blobs = blobs
    }
}

/// 取色用的 HSB 值。只在播放页内部用。
struct AudiobookCoverColor: Equatable {
    let hue: CGFloat
    let saturation: CGFloat
    let brightness: CGFloat

    /// 中文注释：鲜艳程度：饱和度为主，太暗的打折扣。
    var vividness: CGFloat {
        return self.saturation * min(self.brightness + 0.3, 1)
    }

    /// 中文注释：饱和度提到 1.5 倍、至少 0.45（偏灰的封面提了 1.5 倍还是灰，2026-10-24 真机）；本来近乎灰（< 0.08）的不提。
    func boosted() -> AudiobookCoverColor {
        guard self.saturation >= 0.08 else {
            return self
        }
        return AudiobookCoverColor(hue: self.hue, saturation: max(min(self.saturation * 1.5, 1), 0.45), brightness: self.brightness)
    }

    var color: Color {
        return Color(hue: Double(self.hue), saturation: Double(self.saturation), brightness: Double(self.brightness))
    }

    func adjusted(saturationCap: CGFloat, brightness: CGFloat) -> AudiobookCoverColor {
        return AudiobookCoverColor(hue: self.hue, saturation: min(self.saturation, saturationCap), brightness: brightness)
    }

    func adjusted(saturationCap: CGFloat, brightnessRange: ClosedRange<CGFloat>) -> AudiobookCoverColor {
        let clamped: CGFloat = min(max(self.brightness, brightnessRange.lowerBound), brightnessRange.upperBound)
        return AudiobookCoverColor(hue: self.hue, saturation: min(self.saturation, saturationCap), brightness: clamped)
    }

    /// 中文注释：把封面画进 24×24 的位图，按亮度分位取初值做 8 簇 k-means（6 轮），按簇大小从大到小返回（空簇去掉）。
    /// 8 簇让小块的天空、皮肤等颜色单独成簇，不被大片白云、栅栏平均成灰（5 簇时 Tom Sawyer 的蓝天被并掉）。
    /// 576 个像素、6 轮，耗时可以忽略；只在拿到封面时调一次。
    static func dominantColors(of image: UIImage, clusterCount: Int = 8) -> [AudiobookCoverColor]? {
        guard let cgImage: CGImage = image.cgImage else {
            return nil
        }
        let side: Int = 24
        var pixels: [UInt8] = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context: CGContext = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else {
            return nil
        }
        var samples: [SIMD3<Double>] = []
        samples.reserveCapacity(side * side)
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 200 {
            samples.append(SIMD3<Double>(Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2])) / 255)
        }
        guard samples.count >= clusterCount else {
            return nil
        }
        let byLuminance: [SIMD3<Double>] = samples.sorted { Self.luminance($0) < Self.luminance($1) }
        var centers: [SIMD3<Double>] = (0..<clusterCount).map { index in
            return byLuminance[(byLuminance.count * (2 * index + 1)) / (2 * clusterCount)]
        }
        var assignments: [Int] = [Int](repeating: 0, count: samples.count)
        for _ in 0..<6 {
            for (sampleIndex, sample) in samples.enumerated() {
                var best: Int = 0
                var bestDistance: Double = .greatestFiniteMagnitude
                for (centerIndex, center) in centers.enumerated() {
                    let delta: SIMD3<Double> = sample - center
                    let distance: Double = (delta * delta).sum()
                    if distance < bestDistance {
                        bestDistance = distance
                        best = centerIndex
                    }
                }
                assignments[sampleIndex] = best
            }
            for centerIndex in centers.indices {
                let members: [SIMD3<Double>] = samples.indices.filter { assignments[$0] == centerIndex }.map { samples[$0] }
                if members.isEmpty == false {
                    centers[centerIndex] = members.reduce(SIMD3<Double>(repeating: 0), +) / Double(members.count)
                }
            }
        }
        let sizes: [Int] = centers.indices.map { centerIndex in assignments.filter { $0 == centerIndex }.count }
        let order: [Int] = centers.indices.filter { sizes[$0] > 0 }.sorted { sizes[$0] > sizes[$1] }
        return order.map { centerIndex in
            let rgb: SIMD3<Double> = centers[centerIndex]
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            UIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            return AudiobookCoverColor(hue: hue, saturation: saturation, brightness: brightness)
        }
    }

    private static func luminance(_ rgb: SIMD3<Double>) -> Double {
        return 0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
    }
}

/// 流动背景：平时是 MeshGradient 流体；低电量模式、减弱动态效果时退回色块漂移。
struct AudiobookFlowingBackdrop: View {
    let palette: AudiobookBackdropPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        Group {
            if self.reduceMotion || self.isLowPowerMode {
                AudiobookDriftingBackdrop(palette: self.palette)
            } else {
                AudiobookMeshBackdrop(palette: self.palette)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            // 中文注释：通知在任意线程发出；用 async 序列在视图的主 actor 任务里读，开关低电量模式时即时切换。
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                self.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}

/// 中文注释：MeshGradient 流体（2026-10-24 用户选定）：3×3 网格，四角是底色，边中点与中心在三个封面色之间轮换（10 秒一圈），
/// 边中点沿边、中心点在画面里缓慢游走；TimelineView 每秒最多 30 帧，App 不在前台时暂停。底部加暗让白字可读。
/// 真机读数（iPhone 15，不限帧时）：比色块漂移多约 6.5 个点 App CPU、GPU 忙碌多 25–40%，所以限 30 帧。
struct AudiobookMeshBackdrop: View {
    let palette: AudiobookBackdropPalette

    @Environment(\.scenePhase) private var scenePhase: ScenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: self.scenePhase != .active)) { context in
            let seconds: Double = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
            let s: Float = Float(seconds)
            let ring: [Color] = self.palette.blobs
            let base: Color = self.palette.base
            ZStack {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5 + 0.2 * sin(s * 0.7), 0], [1, 0],
                        [0, 0.5 + 0.2 * sin(s * 0.9)], [0.5 + 0.25 * sin(s * 0.6), 0.5 + 0.2 * cos(s * 0.8)], [1, 0.5 + 0.2 * cos(s * 0.7)],
                        [0, 1], [0.5 + 0.2 * cos(s * 0.5), 1], [1, 1]
                    ],
                    colors: [
                        base, Self.cycle(ring, seconds, phase: 0), base,
                        Self.cycle(ring, seconds, phase: 0.33), Self.cycle(ring, seconds, phase: 0.66), Self.cycle(ring, seconds, phase: 0.15),
                        base, Self.cycle(ring, seconds, phase: 0.5), base
                    ]
                )
                AudiobookBackdropScrim()
            }
        }
    }

    private static func cycle(_ colors: [Color], _ seconds: Double, phase: Double) -> Color {
        let stop: (index: Int, next: Int, fraction: Double) = Self.cycleStop(seconds: seconds, phase: phase, count: colors.count)
        return colors[stop.index].mix(with: colors[stop.next], by: stop.fraction)
    }

    /// 中文注释：颜色轮换的位置：10 秒走完一圈 `count` 个颜色，相邻两色之间缓入缓出；`phase` 是一圈里的起点（0–1）。
    static func cycleStop(seconds: Double, phase: Double, count: Int) -> (index: Int, next: Int, fraction: Double) {
        let lap: Double = (seconds / 10 + phase).truncatingRemainder(dividingBy: 1)
        let position: Double = (lap < 0 ? lap + 1 : lap) * Double(count)
        let index: Int = min(Int(position), count - 1)
        let fraction: Double = (1 - cos(.pi * (position - Double(index)))) / 2
        return (index, (index + 1) % count, fraction)
    }
}

/// 底部加暗让白字可读；两种背景共用。
struct AudiobookBackdropScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: CatalogPalette.immersiveScrim.opacity(0.22), location: 0),
                .init(color: CatalogPalette.immersiveScrim.opacity(0.11), location: 0.4),
                .init(color: CatalogPalette.immersiveScrim, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// 色块漂移（低电量模式、减弱动态效果时的退路）：底色 + 三团柔边色块各自 16 / 19 / 22 秒往返漂移，底部加暗让白字可读。
struct AudiobookDriftingBackdrop: View {
    let palette: AudiobookBackdropPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.scenePhase) private var scenePhase: ScenePhase
    @State private var isDrifting: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let width: CGFloat = geometry.size.width
            let height: CGFloat = geometry.size.height
            ZStack {
                self.palette.base
                self.blob(self.palette.blobs[0], diameter: width * 1.18)
                    .scaleEffect(self.isDrifting ? 1.18 : 1)
                    .offset(x: -width * 0.32 + (self.isDrifting ? 70 : 0), y: -height * 0.28 + (self.isDrifting ? 60 : 0))
                    .animation(self.drift(seconds: 16), value: self.isDrifting)
                self.blob(self.palette.blobs[1], diameter: width * 1.23)
                    .scaleEffect(self.isDrifting ? 0.92 : 1.1)
                    .offset(x: width * 0.42 + (self.isDrifting ? -80 : 0), y: height * 0.08 + (self.isDrifting ? -40 : 0))
                    .animation(self.drift(seconds: 19), value: self.isDrifting)
                self.blob(self.palette.blobs[2], diameter: width * 1.13)
                    .scaleEffect(self.isDrifting ? 1.12 : 0.95)
                    .offset(x: -width * 0.12 + (self.isDrifting ? 40 : 0), y: height * 0.42 + (self.isDrifting ? -70 : 0))
                    .animation(self.drift(seconds: 22), value: self.isDrifting)
                AudiobookBackdropScrim()
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .animation(.easeInOut(duration: 0.6), value: self.palette)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            self.updateDrifting()
        }
        .onChange(of: self.scenePhase) {
            self.updateDrifting()
        }
        .onChange(of: self.reduceMotion) {
            self.updateDrifting()
        }
    }

    private func blob(_ color: Color, diameter: CGFloat) -> some View {
        return Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.9), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.5
                )
            )
            .frame(width: diameter, height: diameter)
    }

    /// 中文注释：漂移中用往返的长动画；停下时用 1.2 秒缓回原位，不跳。
    private func drift(seconds: Double) -> Animation {
        return self.isDrifting
            ? .easeInOut(duration: seconds).repeatForever(autoreverses: true)
            : .easeInOut(duration: 1.2)
    }

    private func updateDrifting() {
        self.isDrifting = self.reduceMotion == false && self.scenePhase == .active
    }
}
