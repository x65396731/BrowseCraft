import SwiftUI

/// 详情页简介块里的相关链接（漫画详情的相册、二级页）。
struct DetailRelatedLink: Identifiable, Hashable {
    let title: String
    let url: URL

    var id: String {
        return "\(self.title)|\(self.url.absoluteString)"
    }
}

/// 骨架条：圆角 3、高 12、次级填充底；宽 nil 即通栏。
struct DetailSkeletonBar: View {
    let width: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(CatalogPalette.fillBackground)
            .frame(width: self.width, height: 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// 简介位置的骨架：短标题条 + 通栏 + 240pt（影视、漫画详情「正在取详情」）。
struct DetailSynopsisSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailSkeletonBar(width: 36)
            DetailSkeletonBar(width: nil)
            DetailSkeletonBar(width: 240)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .accessibilityHidden(true)
    }
}

/// 三个详情页同一个简介块（2026-10-11 复审「跨页复制」收敛，此前三份各写一遍）：
/// 分区标题「简介」+ 正文三行折叠、点「展开 / 收起」；下面是没落在头部的元数据行，再下面是相关链接。
/// 正文为 nil 时不出折叠按钮；全部为空时由调用方不渲染本块。
struct DetailSynopsisSection: View {
    let description: String?
    var lines: [String] = []
    var links: [DetailRelatedLink] = []
    let accent: Color
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("video_detail_section_synopsis", comment: ""))
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
            if let description: String = self.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(self.isExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(self.lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(self.links) { link in
                Link(destination: link.url) {
                    HStack(spacing: 4) {
                        Text(link.title)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(self.accent)
                    .frame(minHeight: 44, alignment: .leading)
                }
            }
            if self.description != nil {
                Button(NSLocalizedString(self.isExpanded ? "video_detail_collapse" : "video_detail_expand", comment: "")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.isExpanded.toggle()
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(self.accent)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}
