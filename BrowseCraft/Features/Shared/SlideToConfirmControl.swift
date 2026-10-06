import SwiftUI
import UIKit

// 中文注释：滑动确认控件（`docs/design/Generation-Input-Page-Redesign-Design.md` 第三节，用户 2026-10-06 指定）：
// 胶囊轨道、左端 44pt 圆形滑块带箭头、中间一句文案；把滑块拖到右端打一次触觉反馈再触发，没拖到底松手弹回。
// 只有扣 coin 的动作用它，普通动作仍是按钮。两套视觉：普通档动作蓝素底；困难档粉彩渐变淡底铺流光点阵、
// 饱和渐变文字与滑块，不加描边（用户 2026-10-07 认可的那版）。进行中滑块停在右端内转圈、文案换成进行中的那句。

struct SlideToConfirmControl: View {
    enum Tone {
        case action
        case spectrum
    }

    let title: String
    let busyTitle: String
    var tone: Tone = .action
    var isBusy: Bool = false
    var isEnabled: Bool = true
    let onConfirm: () -> Void

    /// 中文注释：拖动中的位移用 `@GestureState`——手势结束或被 ScrollView 接管取消时系统自动弹回 0，不会卡在半路；
    /// 拖到底之后的「停在右端」由 `isHeldAtEnd` 承担。
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.3))) private var dragOffset: CGFloat = 0
    @State private var isHeldAtEnd: Bool = false

    private static let height: CGFloat = 50
    private static let knobSize: CGFloat = 44
    private static let inset: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let maxOffset: CGFloat = max(0, proxy.size.width - Self.knobSize - Self.inset * 2)
            let offset: CGFloat = (self.isBusy || self.isHeldAtEnd) ? maxOffset : self.dragOffset
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(self.trackFill)
                if self.tone == .spectrum {
                    // 中文注释：这里不加渐变发光描边——那是困难按钮的（用户 2026-10-07 明确：喜欢那种按钮不等于滑动确认也要）。
                    DotMatrixTrack(
                        baseColor: .secondary,
                        litFraction: 1,
                        intensity: 0.55,
                        isAnimated: self.isEnabled && self.isBusy == false
                    )
                }
                Text(self.isBusy ? self.busyTitle : self.title)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(self.titleStyle)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, Self.knobSize / 2)
                    .padding(.horizontal, 8)
                    .opacity(1 - Double(min(1, offset / max(1, maxOffset))) * 0.7)
                Circle()
                    .fill(self.knobFill)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .shadow(color: self.knobGlow, radius: self.tone == .spectrum ? 6 : 4, y: self.tone == .spectrum ? 0 : 2)
                    .overlay {
                        if self.isBusy {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .offset(x: Self.inset + offset)
                    .gesture(self.dragGesture(maxOffset: maxOffset))
            }
        }
        .frame(height: Self.height)
        .opacity(self.isEnabled ? 1 : 0.45)
        .animation(.spring(duration: 0.3), value: self.isHeldAtEnd)
        .onChange(of: self.isBusy) { _, busy in
            // 中文注释：进行中结束后滑块回到左端，下一次还得重新滑到底。
            if busy == false {
                self.isHeldAtEnd = false
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.isBusy ? self.busyTitle : self.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(self.isEnabled && self.isBusy == false ? "" : NSLocalizedString("generation_input_control_unavailable", comment: ""))
        .accessibilityAction {
            guard self.isEnabled, self.isBusy == false else {
                return
            }
            self.onConfirm()
        }
    }

    private var titleStyle: AnyShapeStyle {
        return self.tone == .spectrum ? AnyShapeStyle(CatalogPalette.spectrumVividGradient) : AnyShapeStyle(CatalogPalette.addAction)
    }

    private var trackFill: AnyShapeStyle {
        return self.tone == .spectrum ? AnyShapeStyle(CatalogPalette.spectrumFill) : AnyShapeStyle(CatalogPalette.settingsIconFill)
    }

    private var knobFill: AnyShapeStyle {
        return self.tone == .spectrum
            ? AnyShapeStyle(LinearGradient(colors: CatalogPalette.spectrumVividColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(CatalogPalette.addAction)
    }

    private var knobGlow: Color {
        return self.tone == .spectrum ? CatalogPalette.spectrumColor(at: 0.4).opacity(0.7) : CatalogPalette.addAction.opacity(0.35)
    }

    private var canDrag: Bool {
        return self.isEnabled && self.isBusy == false && self.isHeldAtEnd == false
    }

    private func dragGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating(self.$dragOffset) { value, state, transaction in
                guard self.canDrag else {
                    return
                }
                // 中文注释：拖动中不走弹簧，滑块跟手；松手弹回的动画由 `resetTransaction` 给。
                transaction.animation = nil
                state = min(maxOffset, max(0, value.translation.width))
            }
            .onEnded { value in
                guard self.canDrag else {
                    return
                }
                let offset: CGFloat = min(maxOffset, max(0, value.translation.width))
                if offset >= maxOffset - 2 {
                    self.isHeldAtEnd = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    self.onConfirm()
                }
            }
    }
}
