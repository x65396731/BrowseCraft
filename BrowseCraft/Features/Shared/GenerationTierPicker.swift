import SwiftUI
import UIKit

// 中文注释：取页方式的两档按钮（`docs/design/Generation-Input-Page-Redesign-Design.md` 第三节，用户 2026-10-07 裁定：
// 从点阵滑杆改回两个按钮，只有「困难」按钮带效果，且不要点阵流光）。普通 = 素底胶囊，选中时添加蓝 12% 底 + 蓝字；
// 困难 = 粉彩渐变淡底 + 渐变发光描边（`SpectrumGlowBorder`，与内购页套餐按钮同一种语言），选中时描边更粗更亮、字用饱和渐变。

struct GenerationTierPicker: View {
    @Binding var tier: GenerationAcquisitionTier
    let normalPrice: Int
    let hardPrice: Int
    var isEnabled: Bool = true

    private static let height: CGFloat = 44

    var body: some View {
        HStack(spacing: 10) {
            self.normalButton
            self.hardButton
        }
        .opacity(self.isEnabled ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.2), value: self.tier)
    }

    private var normalButton: some View {
        let isSelected: Bool = self.tier == .normal
        return Button {
            self.select(.normal)
        } label: {
            Text(self.title(for: .normal))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? CatalogPalette.addAction : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .background(isSelected ? CatalogPalette.settingsIconFill : CatalogPalette.fillBackground, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(CatalogPalette.addAction.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(self.isEnabled == false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 中文注释：困难按钮无论选没选中都带渐变描边，选中时更粗更亮——用户只要这一颗有效果。
    private var hardButton: some View {
        let isSelected: Bool = self.tier == .hard
        return Button {
            self.select(.hard)
        } label: {
            Text(self.title(for: .hard))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? AnyShapeStyle(CatalogPalette.spectrumVividGradient) : AnyShapeStyle(Color.primary))
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .background(CatalogPalette.spectrumFill, in: Capsule(style: .continuous))
                .overlay(SpectrumGlowBorder(shape: Capsule(style: .continuous), isActive: isSelected))
        }
        .buttonStyle(.plain)
        .disabled(self.isEnabled == false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 「普通 · 100 coin」这样的标题。
    private func title(for tier: GenerationAcquisitionTier) -> String {
        let name: String = tier == .hard
            ? NSLocalizedString("generation_input_tier_hard", comment: "")
            : NSLocalizedString("generation_input_tier_normal", comment: "")
        let price: String = String(
            format: NSLocalizedString("generation_input_tier_price", comment: ""),
            tier == .hard ? self.hardPrice : self.normalPrice
        )
        return "\(name) · \(price)"
    }

    private func select(_ newTier: GenerationAcquisitionTier) {
        guard newTier != self.tier else {
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        self.tier = newTier
    }
}
