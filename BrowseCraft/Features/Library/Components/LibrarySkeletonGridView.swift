import SwiftUI

// 中文注释：LibrarySkeletonGridView 是首屏加载的骨架网格，替掉此前的转圈 + 两行文案。

/// 中文注释：骨架网格与两套真列表同形——3 列、列距 12、行距 16、外边距 16、封面 129:194、
/// 标题区固定 30pt（见 `VideoContentGridView` 与 `ComicLibraryCardView`），所以真内容到达时不跳版。
/// 用骨架而不是转圈加文案有两个理由：它天然长在正文那一层，不会和空态挤成上下两块；
/// 它不说话，也就不会出现"正在取数据"与"下拉刷新来填充"互相打架的文案。
struct LibrarySkeletonGridView: View {
    /// 中文注释：铺满一屏即可，9 张是 3 列 × 3 行；再多只是白耗布局。
    private let placeholderCount: Int = 9
    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var isDimmed: Bool = false

    var body: some View {
        LazyVGrid(columns: self.gridColumns, spacing: 16) {
            ForEach(0..<self.placeholderCount, id: \.self) { _ in
                self.card
            }
        }
        .padding(16)
        .opacity(self.isDimmed ? 0.45 : 1)
        .animation(self.breathingAnimation, value: self.isDimmed)
        .onAppear {
            guard self.reduceMotion == false else {
                return
            }
            self.isDimmed = true
        }
        // 中文注释：骨架对读屏只报一句"正在载入"，不要逐块播报九个空占位。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString("library_body_loading_accessibility", comment: "骨架屏无障碍标签")))
    }

    private var breathingAnimation: Animation? {
        guard self.reduceMotion == false else {
            return nil
        }
        return Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(self.placeholderFill)
                .aspectRatio(129.0 / 194.0, contentMode: .fit)

            VStack(alignment: .leading, spacing: 4) {
                // 中文注释：对应真卡片里固定 30pt 的两行标题区。
                VStack(alignment: .leading, spacing: 4) {
                    self.bar(widthRatio: 1)
                    self.bar(widthRatio: 0.62)
                }
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .topLeading)

                // 中文注释：对应 latestText 那一行。
                self.bar(widthRatio: 0.42)
            }
        }
    }

    /// 中文注释：占位条按卡片宽度取比例，不写死点数——iPad 上列宽不一样。
    private func bar(widthRatio: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(self.placeholderFill)
                .frame(width: proxy.size.width * widthRatio, height: 12)
        }
        .frame(height: 12)
    }

    private var placeholderFill: Color {
        return Color(.secondarySystemFill)
    }
}
