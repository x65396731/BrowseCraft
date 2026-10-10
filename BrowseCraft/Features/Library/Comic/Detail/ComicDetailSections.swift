import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

// 中文注释：漫画详情页目录之外的各块（`docs/design/Comic-Detail-Page-Redesign-Design.md` 第五、六、八节）：
// 头部、标签条、继续阅读、受限横幅、简介。颜色全部取 `CatalogStyle.swift`，本页不新增色值。

/// 头部 + 标签条 + 继续阅读 + 受限横幅 + 简介；它们都随内容滚走。
struct ComicDetailHeaderSection: View {
    let viewModel: ComicDetailViewModel
    let style: CatalogKindStyle
    /// 点继续卡片 / 按钮要开的目的地，由外层打开阅读器。
    let openReaderDestination: (ComicReaderDestination) -> Void
    @State private var isSynopsisExpanded: Bool = false
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    private static let coverSize: CGSize = CGSize(width: 112, height: 150)

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.tagsRow
            self.continueSection
            self.synopsisSection
        }
    }

    // MARK: - 头部（第五节）

    /// 漫画类型色 8% 淡底（深色 10%），顶到状态栏：底色向上多铺一段盖住安全区。
    private var tint: Color {
        return self.style.accent.opacity(self.colorScheme == .dark ? 0.10 : 0.08)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ItemThumbnailImageView(
                urlString: self.viewModel.coverURLString,
                refererURLString: self.viewModel.item.detailURL,
                requestConfig: self.viewModel.detailCoverRequestConfig,
                placeholderImageName: "ComicDetailPlaceholder"
            )
            .frame(width: Self.coverSize.width, height: Self.coverSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: CatalogPalette.cardShadow, radius: 9, y: 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(self.viewModel.displayTitle)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .accessibilityAddTraits(.isHeader)

                if let author: String = self.viewModel.authorText {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                self.badgeRow

                if let updateLine: String = self.viewModel.updateLineText {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10, weight: .bold))
                            .accessibilityHidden(true)
                        Text(updateLine)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(self.style.accent)
                }

                Text(verbatim: "\(self.viewModel.source.name) · \(self.viewModel.sourceHostText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        // 中文注释：返回 / 收藏按钮是安全区 inset，内容从它们下面开始；淡底向上多铺一段盖住 inset 与状态栏。
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            self.tint
                .padding(.top, -300)
        }
    }

    /// 徽章行：状态用类型色淡底 + 类型色字，分类与语言次级填充底；一个都没有不出这行。
    @ViewBuilder
    private var badgeRow: some View {
        let status: String? = self.viewModel.statusText
        let others: [String] = [self.viewModel.categoryText, self.viewModel.languageText].compactMap { $0 }
        if status != nil || others.isEmpty == false {
            HStack(spacing: 6) {
                if let status: String = status {
                    self.badge(status, foreground: self.style.accent, background: self.style.accent.opacity(0.12))
                }
                ForEach(others, id: \.self) { text in
                    self.badge(text, foreground: .secondary, background: CatalogPalette.fillBackground)
                }
            }
        }
    }

    private func badge(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(background, in: Capsule())
    }

    @ViewBuilder
    private var tagsRow: some View {
        let tags: [String] = self.viewModel.tags
        if tags.isEmpty == false {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(CatalogPalette.fillBackground, in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - 继续阅读（第六节）

    @ViewBuilder
    private var continueSection: some View {
        if self.viewModel.didLoad == false, self.viewModel.isLoading {
            Capsule()
                .fill(CatalogPalette.fillBackground)
                .frame(height: 50)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .accessibilityHidden(true)
        } else if self.viewModel.chapters.isEmpty == false, let destination: ComicReaderDestination = self.viewModel.continueDestination {
            if let title: String = self.viewModel.continueCardTitle {
                self.continueCard(title: title, destination: destination)
            } else {
                self.startButton(destination: destination)
            }
        }
    }

    /// 有历史：通栏卡片——上次页面缩略图 + 「继续阅读」+ 章节名 + 「13 / 45 页 · 昨天 21:40」+ 进度条（共享 `DetailContinueCard`）。
    private func continueCard(title: String, destination: ComicReaderDestination) -> some View {
        DetailContinueCard(
            label: NSLocalizedString("comic_detail_continue", comment: ""),
            title: title,
            subtitle: self.viewModel.continueCardSubtitle,
            progress: self.viewModel.continueProgress,
            iconName: "book.pages.fill",
            accent: self.style.accent,
            action: {
                self.openDestination(destination)
            }
        ) {
            // 中文注释：上次页面的图走 pipeline 解密的站（めちゃコミック）直接请求不出来，退到封面再退到占位图。
            ItemThumbnailImageView(
                urlString: self.viewModel.continueThumbnailURLString,
                refererURLString: self.viewModel.continueThumbnailRefererURLString,
                requestConfig: self.viewModel.detailCoverRequestConfig,
                placeholderImageName: "ComicDetailPlaceholder",
                fallbackURLString: self.viewModel.coverURLString
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func startButton(destination: ComicReaderDestination) -> some View {
        DetailStartButton(iconName: "book.pages.fill", title: self.viewModel.startButtonTitle, accent: self.style.accent) {
            self.openDestination(destination)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func openDestination(_ destination: ComicReaderDestination) {
        self.openReaderDestination(destination)
    }

    // MARK: - 简介（第五节）

    @ViewBuilder
    private var synopsisSection: some View {
        if self.viewModel.didLoad == false, self.viewModel.isLoading {
            DetailSynopsisSkeleton()
        } else if self.viewModel.hasSynopsisSection {
            DetailSynopsisSection(
                description: self.viewModel.descriptionText,
                lines: self.viewModel.attributeLines,
                links: self.viewModel.relatedLinks,
                accent: self.style.accent,
                isExpanded: self.$isSynopsisExpanded
            )
        }
    }
}
