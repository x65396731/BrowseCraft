import SwiftUI

// 中文注释：LibraryPlaceholderView 是 Library 正文的空态与失败态，两者共用同一个版面。

/// 中文注释：这块占位**必须长在 ScrollView 的内容里**，不能挂 `.overlay`。
/// SwiftUI 里 `Image` 和 `Text` 是可命中的，浮在滚动视图外面的话，用户最自然的拖拽起点
/// （图标和那行字）会把手势吃掉，滚动视图收不到，表现为"中间这块拉不动、旁边空白能拉"。
/// 放进内容层并用 `containerRelativeFrame` 撑满视口高度之后，整屏任意位置都能下拉。
///
/// 重试入口是下拉刷新手势，不放按钮（导航栏的刷新按钮已在 9d22cb2 删掉，顶部拉动刷新顶替了它）。
/// 手势没有可见入口，所以可发现性全靠这里：文案点名"下拉"，下面再给一个向下的示意。
struct LibraryPlaceholderView: View {
    let systemImage: String
    let title: String
    let message: String
    let pullHint: String
    /// 中文注释：同 `EmptyStateView`——给了插画就画插画，没给退回系统符号。
    var illustration: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var isHintLowered: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            EmptyStateIconView(systemImage: self.systemImage, illustration: self.illustration)

            Text(self.title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(self.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            self.pullHintView
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        // 中文注释：撑满滚动视口再居中，一是让版面落在 tab 条与底部标签栏之间，
        // 二是让整屏都属于滚动视图，随便哪里都能下拉。
        .containerRelativeFrame(.vertical, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private var pullHintView: some View {
        VStack(spacing: 4) {
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 20, weight: .semibold))
                .offset(y: self.isHintLowered ? 4 : -2)
                .animation(self.hintAnimation, value: self.isHintLowered)

            Text(self.pullHint)
                .font(.footnote)
        }
        .foregroundColor(.secondary)
        .onAppear {
            guard self.reduceMotion == false else {
                return
            }
            self.isHintLowered = true
        }
    }

    private var hintAnimation: Animation? {
        guard self.reduceMotion == false else {
            return nil
        }
        return Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
    }
}
