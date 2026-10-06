import SwiftUI

// 中文注释：点阵轨道——6pt 间距的圆点，一道光沿轨道方向循环流动（`docs/design/Generation-Input-Page-Redesign-Design.md` 第三节，
// 用户 2026-10-07 要求点阵要有动画）。只给困难档的滑动确认用（用户裁定按钮不要这种动画）：亮起的点按位置取
// `CatalogPalette.spectrumColor`（粉彩的浅蓝 → 薰衣草 → 浅粉 → 杏色），光扫过时点变亮、略微变大。系统「减弱动态效果」打开时静止不动。

struct DotMatrixTrack: View, Animatable {
    var baseColor: Color
    /// 亮起的部分占宽度的比例（0 … 1）。
    var litFraction: CGFloat
    /// 发光色；nil 不发光。
    var glowColor: Color? = nil
    /// 亮起部分的整体不透明度倍数（滑动确认的底纹要淡一些）。
    var intensity: CGFloat = 1
    var isAnimated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated var animatableData: CGFloat {
        get { self.litFraction }
        set { self.litFraction = newValue }
    }

    private static let dotSpacing: CGFloat = 6
    private static let dotRadius: CGFloat = 1.4
    /// 一道光从左端外侧扫到右端外侧的时长（含两端各 3σ 的看不见的余量）。
    private static let sweepDuration: TimeInterval = 2.2
    /// 光斑的半宽（高斯 σ）。
    private static let sweepSigma: CGFloat = 26

    var body: some View {
        let animated: Bool = self.isAnimated && self.reduceMotion == false
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animated == false)) { timeline in
            Canvas { context, size in
                let progress: CGFloat = animated
                    ? CGFloat((timeline.date.timeIntervalSinceReferenceDate / Self.sweepDuration)
                        .truncatingRemainder(dividingBy: 1))
                    : -1
                self.draw(in: &context, size: size, sweepProgress: progress)
            }
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(color: self.glowColor?.opacity(0.55) ?? .clear, radius: self.glowColor == nil ? 0 : 3)
        .accessibilityHidden(true)
    }

    /// 中文注释：每帧重画全部圆点。点数不多（滑动确认八行、几十列），30 fps 下开销可忽略。
    private func draw(in context: inout GraphicsContext, size: CGSize, sweepProgress: CGFloat) {
        let spacing: CGFloat = Self.dotSpacing
        let radius: CGFloat = Self.dotRadius
        let litWidth: CGFloat = size.width * min(1, max(0, self.litFraction))
        // 光斑中心：从左端外侧 3σ 走到右端外侧 3σ（3σ 处亮度约 1%），首尾都看不见光斑，循环接缝才不跳。
        let sigma: CGFloat = Self.sweepSigma
        let margin: CGFloat = sigma * 3
        let head: CGFloat? = sweepProgress >= 0 ? (-margin + sweepProgress * (size.width + margin * 2)) : nil
        var y: CGFloat = spacing / 2
        while y < size.height {
            var x: CGFloat = spacing / 2
            while x < size.width {
                var brightness: CGFloat = 0
                if let head: CGFloat {
                    let distance: CGFloat = x - head
                    brightness = exp(-(distance * distance) / (2 * sigma * sigma))
                }
                let isLit: Bool = x <= litWidth
                let color: Color = isLit
                    ? CatalogPalette.spectrumColor(at: x / max(1, size.width))
                        .opacity(Double(self.intensity * (0.6 + 0.4 * brightness)))
                    : self.baseColor.opacity(Double(0.3 + 0.25 * brightness))
                let dotRadius: CGFloat = radius * (1 + (isLit ? 0.35 : 0.15) * brightness)
                let rect: CGRect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                x += spacing
            }
            y += spacing
        }
    }
}
