import SwiftUI

// 中文注释：漫画阅读器换话手势的组件（docs/design/Comic-Reader-Chapter-Swipe-Design.md）：
// 拉出距离、拉动状态、拉出空白里的提示、换话中的贴边等待浮层。

/// 中文注释：换话手势的边。顶部下拉回上一话（本话没有页面时是重试），底部上拉进下一话。
enum ReaderPullEdge: Equatable {
    case top
    case bottom

    var direction: ReaderChapterNavigationDirection {
        switch self {
        case .top:
            return .previous
        case .bottom:
            return .next
        }
    }
}

/// 中文注释：内容被拉出顶端或底端的距离（pt，取整）；没拉出时为 0。
struct ReaderOverscroll: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0

    init() {}

    /// 中文注释：`containerSize` 是扣掉上下内边距（标题栏、底部安全区）后的可视高度，
    /// 所以滚到底时的偏移 = 内容高 − 可视高 − 顶部内边距（模拟器实测：内边距 116 / 34、可视高 724）。
    init(geometry: ScrollGeometry) {
        let minimumOffsetY: CGFloat = -geometry.contentInsets.top
        let maximumOffsetY: CGFloat = max(
            minimumOffsetY,
            geometry.contentSize.height - geometry.containerSize.height - geometry.contentInsets.top
        )
        self.top = max(0, minimumOffsetY - geometry.contentOffset.y).rounded()
        self.bottom = max(0, geometry.contentOffset.y - maximumOffsetY).rounded()
    }

    func distance(_ edge: ReaderPullEdge) -> CGFloat {
        switch edge {
        case .top:
            return self.top
        case .bottom:
            return self.bottom
        }
    }
}

/// 中文注释：换话手势的滚动状态。不放进 `ReaderView` 的 `@State`：拉动的每一帧只刷新提示，不重算整列漫画页。
@MainActor
@Observable
final class ReaderPullTracker {
    /// 中文注释：拉过这个距离才进入「松手…」态；实施后在真机上微调。
    static let triggerDistance: CGFloat = 72

    var overscroll: ReaderOverscroll = ReaderOverscroll()
    var phase: ScrollPhase = .idle
    /// 中文注释：手指还按着、已经拉过触发距离的那一边。
    var armedEdge: ReaderPullEdge?
    /// 中文注释：松手时已拉过触发距离的那一边；等滚动回到静止才发起，中途不碰偏移量。
    var releasedEdge: ReaderPullEdge?

    func reset() {
        self.overscroll = ReaderOverscroll()
        self.armedEdge = nil
        self.releasedEdge = nil
    }
}

/// 中文注释：拉出空白里的一行提示。
struct ReaderPullHintContent: Equatable {
    let text: String
    let showsChevron: Bool
}

/// 中文注释：顶部与底部两处拉动提示，外加拉过触发距离时的一次轻震。只负责显示，不接收触摸。
struct ReaderPullHintsOverlay: View {
    let tracker: ReaderPullTracker
    let content: @MainActor (ReaderPullEdge, Bool) -> ReaderPullHintContent?

    var body: some View {
        VStack(spacing: 0) {
            self.hint(for: .top)
            Spacer(minLength: 0)
            self.hint(for: .bottom)
        }
        .allowsHitTesting(false)
        .sensoryFeedback(.impact(weight: .light), trigger: self.tracker.armedEdge) { _, newValue in
            return newValue != nil
        }
    }

    @ViewBuilder
    private func hint(for edge: ReaderPullEdge) -> some View {
        let distance: CGFloat = self.tracker.overscroll.distance(edge)
        let isArmed: Bool = self.tracker.armedEdge == edge || self.tracker.releasedEdge == edge
        if distance > 0, let hint: ReaderPullHintContent = self.content(edge, isArmed) {
            ReaderPullHint(edge: edge, content: hint, isArmed: isArmed, distance: distance)
        }
    }
}

/// 中文注释：与失败态「下拉重试」同一套：`chevron.compact` 20pt semibold + footnote，间距 4，居中。
/// 拉动中次级色；拉过触发距离后主色 semibold、箭头翻转。
private struct ReaderPullHint: View {
    let edge: ReaderPullEdge
    let content: ReaderPullHintContent
    let isArmed: Bool
    let distance: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            if self.content.showsChevron {
                Image(systemName: self.chevronName)
                    .font(.system(size: 20, weight: .semibold))
            }
            Text(self.content.text)
                .font(.footnote.weight(self.isArmed ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(self.isArmed ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: self.distance)
        .clipped()
        .opacity(min(1, self.distance / 32))
        .accessibilityHidden(true)
    }

    private var chevronName: String {
        let pointsUp: Bool = (self.edge == .bottom) != self.isArmed
        return pointsUp ? "chevron.compact.up" : "chevron.compact.down"
    }
}

/// 中文注释：换话中的贴边浮层：中号品牌等待标记 + 「正在打开…」。进下一话贴底、回上一话贴在标题栏下；
/// 不属于滚动内容、不改偏移量、不接收触摸，当前这一话照常可滑。
struct ReaderChapterSwitchWaitingBand: View {
    let edge: ReaderPullEdge
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            BrandWaitingMark(size: .medium)
            Text(self.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(CatalogPalette.plainBackground)
        .overlay(alignment: self.edge == .top ? .bottom : .top) {
            Divider()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
