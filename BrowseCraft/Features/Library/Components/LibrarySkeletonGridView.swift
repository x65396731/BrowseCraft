import SwiftUI

// 中文注释：LibrarySkeletonGridView 是首屏加载的骨架网格，替掉此前的转圈 + 两行文案。

/// 中文注释：骨架与真网格同形，真内容到达时不跳版。视频（书籍暂同）是海报墙——两列（最小宽 160 自适应）、列距 14、
/// 行距 20、封面 2:3 圆角 14、标题区固定 40pt（见 `VideoContentGridView`）；漫画是封面墙——三列（最小宽 104 自适应）、
/// 列距 12、行距 18、封面圆角 10、标题两行 34pt + 最新话一行（见 `ComicLibraryCardView`）。页边距都是 20。
/// 用骨架而不是转圈加文案有两个理由：它天然长在正文那一层，不会和空态挤成上下两块；
/// 它不说话，也就不会出现"正在取数据"与"下拉刷新来填充"互相打架的文案。
struct LibrarySkeletonGridView: View {
    enum Layout {
        case posterWall
        case comicWall
    }

    var layout: Layout = .posterWall

    /// 中文注释：铺满一屏即可：两列 × 3 行 6 张、三列 × 3 行 9 张；再多只是白耗布局。
    private var placeholderCount: Int {
        return self.layout == .comicWall ? 9 : 6
    }

    private var gridColumns: [GridItem] {
        switch self.layout {
        case .posterWall:
            return [GridItem(.adaptive(minimum: 160), spacing: 14)]
        case .comicWall:
            return [GridItem(.adaptive(minimum: 104), spacing: 12)]
        }
    }

    private var rowSpacing: CGFloat {
        return self.layout == .comicWall ? 18 : 20
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var isDimmed: Bool = false

    var body: some View {
        LazyVGrid(columns: self.gridColumns, spacing: self.rowSpacing) {
            ForEach(0..<self.placeholderCount, id: \.self) { _ in
                self.card
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .opacity(self.isDimmed ? 0.45 : 1)
        .animation(self.breathingAnimation, value: self.isDimmed)
        .onAppear {
            guard self.reduceMotion == false else {
                return
            }
            self.isDimmed = true
        }
        // 中文注释：骨架对读屏只报一句"正在载入"，不要逐块播报六个空占位。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString("library_body_loading_accessibility", comment: "骨架屏无障碍标签")))
    }

    private var breathingAnimation: Animation? {
        guard self.reduceMotion == false else {
            return nil
        }
        return Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    }

    @ViewBuilder
    private var card: some View {
        switch self.layout {
        case .posterWall:
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(self.placeholderFill)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)

                // 中文注释：对应真卡片里固定 40pt 的两行标题区。
                VStack(alignment: .leading, spacing: 6) {
                    self.bar(widthRatio: 1)
                    self.bar(widthRatio: 0.62)
                }
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .topLeading)
            }
        case .comicWall:
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(self.placeholderFill)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)

                // 中文注释：对应真卡片里 34pt 的两行标题区与下面一行最新话。
                VStack(alignment: .leading, spacing: 6) {
                    self.bar(widthRatio: 1)
                    self.bar(widthRatio: 0.62)
                }
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .topLeading)
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
        return CatalogPalette.fillBackground
    }
}
