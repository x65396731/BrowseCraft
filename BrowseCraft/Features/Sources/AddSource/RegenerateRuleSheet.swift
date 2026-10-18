import SwiftUI

// 中文注释：重新生成面板（`docs/design/Generation-Input-Page-Redesign-Design.md` 第三节「重新生成面板」，用户 2026-10-19 定）。
// 网址输入页两处重新生成链接（「不用现成的，重新生成」「规则用不了？重新生成」）都拉起这一面板，不用系统确认框：
// 说明会再扣 coin、建议先试用，再给与输入页同一套的取页方式卡、余额说明与「滑动重新生成」。只有扣 coin 的动作要滑。

struct RegenerateRuleSheet: View {
    /// 中文注释：与输入页共用同一个档位状态——在面板里切档，回到输入页仍是这一档。
    @Binding var tier: GenerationAcquisitionTier
    let normalPrice: Int
    let hardPrice: Int
    /// 中文注释：成功率一行由输入页按当前档拼好传进来（取不到为 nil，不显示），与输入页取页方式卡里那一行同源。
    let rateLine: AttributedString?
    /// 中文注释：余额已知时「当前余额 N · 生成可能失败…」，未知时只写后半句；没有钱包对象时为 nil，整行不出。
    let balanceFooter: String?
    let onConfirm: (GenerationAcquisitionTier) -> Void
    let onCancel: () -> Void

    private var price: Int {
        return self.tier == .hard ? self.hardPrice : self.normalPrice
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CatalogPalette.settingsIcon)
                        .frame(width: 28, height: 28)
                        .background(CatalogPalette.settingsIconFill, in: Circle())
                        .accessibilityHidden(true)
                    Text(NSLocalizedString("generation_input_regenerate_title", comment: "重新生成面板：标题"))
                        .font(.title2.weight(.heavy))
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                Text(NSLocalizedString("generation_input_regenerate_message", comment: "重新生成面板：会再扣 coin、建议先试用"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                SettingsCardGroup(
                    title: NSLocalizedString("video_preflight_tier_title", comment: ""),
                    footer: self.balanceFooter
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        GenerationTierPicker(
                            tier: self.$tier,
                            normalPrice: self.normalPrice,
                            hardPrice: self.hardPrice
                        )
                        Text(NSLocalizedString(
                            self.tier == .hard ? "video_preflight_tier_hard_footer" : "generation_input_tier_normal_footer",
                            comment: ""
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        if let rateLine: AttributedString = self.rateLine {
                            Label {
                                Text(rateLine)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "chart.bar.fill")
                                    .accessibilityHidden(true)
                            }
                            .labelStyle(GenerationRateLabelStyle())
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                }
                .padding(.top, 18)
                SlideToConfirmControl(
                    title: String(format: NSLocalizedString("generation_input_slide_regenerate", comment: ""), self.price),
                    busyTitle: NSLocalizedString("generation_input_submitting", comment: ""),
                    tone: self.tier == .hard ? .spectrum : .action,
                    onConfirm: {
                        self.onConfirm(self.tier)
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 18)
                Button(NSLocalizedString("generation_input_regenerate_cancel", comment: "重新生成面板：取消"), action: self.onCancel)
                    .font(.body)
                    .foregroundStyle(CatalogPalette.addAction)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 8)
            }
            .padding(.bottom, 16)
        }
        .background(CatalogPalette.pageBackground)
        .presentationDetents([.fraction(0.66), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }
}
