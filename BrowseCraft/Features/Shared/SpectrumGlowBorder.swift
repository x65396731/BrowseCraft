import SwiftUI

/// 渐变发光描边：沿形状描一圈粉彩渐变，渐变方向来回缓慢摆动，外加同色光晕——与内购页套餐按钮同一种语言
/// （用户 2026-10-07 指着那种按钮说喜欢）。`isActive` 时描边更粗、光更亮。「减弱动态效果」打开时不摆动。
struct SpectrumGlowBorder<S: InsettableShape>: View {
    let shape: S
    var isActive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Bool = false

    var body: some View {
        self.shape
            .strokeBorder(
                LinearGradient(
                    colors: self.colors,
                    startPoint: self.phase ? .leading : .trailing,
                    endPoint: self.phase ? .trailing : .leading
                ),
                lineWidth: self.isActive ? 2.5 : 1.5
            )
            .shadow(
                color: CatalogPalette.spectrumColor(at: 0.45).opacity(self.isActive ? 0.85 : 0.45),
                radius: self.isActive ? 10 : 5
            )
            .onAppear {
                guard self.reduceMotion == false else {
                    return
                }
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: true)) {
                    self.phase = true
                }
            }
            .accessibilityHidden(true)
    }

    /// 描边用饱和版渐变才看得出轮廓；选中时两端夹白，光扫过去像亮边在走。
    private var colors: [Color] {
        let stops: [Color] = CatalogPalette.spectrumVividColors
        return self.isActive ? [.white] + stops + [.white] : stops.map { $0.opacity(0.55) }
    }
}
