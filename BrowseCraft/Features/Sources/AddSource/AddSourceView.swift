import Foundation
import SwiftUI

// 中文注释：AddSourceView.swift 是中性的添加来源入口，具体导入能力由 SourceImportOption 决定。

struct AddSourceView: View {
    @Bindable var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingComicGeneration: Bool = false
    @State private var isShowingVideoGeneration: Bool = false
    @State private var isShowingBookGeneration: Bool = false
    @State private var unavailableOption: SourceImportOptionKind?

    private let options: [SourceImportOption] = SourceImportOption.defaultOptions

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    self.optionButton(for: .comicSource)
                    self.optionButton(for: .videoSource)
                    self.optionButton(for: .bookSource)
                }
            }
            .navigationTitle("Add Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                }
            }
            // 中文注释：三种 kind 都先进合格入口页引导屏（`EntryPageGuideFlowView`，首次必过一屏），
            // 再进预检输入页——`BC-PAGE-060` 的两个要素此前在 App 里没有任何说明，
            // 要素一还不在预检的判定范围内（只有服务端判），用户只能等生成失败才知道。
            // 中文注释：漫画与视频都指向服务端规则生成入口，两种 kind 的交互完全对称。
            // 本地关键词发现 `ComicDiscoveryView` 就此不再从这里进入，与视频侧的
            // `VideoDiscoveryView` 同一处置。
            .sheet(isPresented: self.$isShowingComicGeneration) {
                EntryPageGuideFlowView(
                    viewModel: self.viewModel,
                    sourceKind: .comic,
                    onFinished: self.returnToSources
                )
            }
            .sheet(isPresented: self.$isShowingVideoGeneration) {
                EntryPageGuideFlowView(
                    viewModel: self.viewModel,
                    sourceKind: .video,
                    onFinished: self.returnToSources
                )
            }
            // 中文注释：读书 kind 与漫画 / 视频同一条服务端规则生成入口（PortalCore 2026-09-13 起接受 sourceKind: book）。
            .sheet(isPresented: self.$isShowingBookGeneration) {
                EntryPageGuideFlowView(
                    viewModel: self.viewModel,
                    sourceKind: .book,
                    onFinished: self.returnToSources
                )
            }
            .alert(
                "Source Type Unavailable",
                isPresented: self.unavailableOptionBinding,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(self.unavailableOptionMessage)
                }
            )
            .onAppear {
                CrashDiagnostics.shared.setScreen(.addSource)
                AppAnalytics.shared.logScreenView(.addSource)
            }
        }
    }

    /// 中文注释：预检页无论怎么结束（提交成功自动返回、按「关闭」、下滑关掉）都回到来源页，
    /// 三种关法一个落点。提交成功的那次用户已经拿到任务回执，规则生成完会自己出现在目录里，
    /// 没有留在这一屏继续点的事。关掉最外层的 `AddSourceView` 会连带收掉它呈现的预检 sheet；
    /// 自动返回已经收掉这一层时，后到的那次 `dismiss()` 是空操作。
    private func returnToSources() {
        self.dismiss()
    }

    @ViewBuilder
    private func optionButton(for kind: SourceImportOptionKind) -> some View {
        if let option: SourceImportOption = self.options.first(where: { item in item.kind == kind }) {
            Button(
                action: {
                    self.select(option)
                },
                label: {
                    Label {
                        Text(option.kind.displayTitle)
                    } icon: {
                        self.optionIcon(for: option.kind)
                    }
                }
            )
        }
    }

    /// 中文注释：三种可生成的 kind 改用自绘的圆形徽章——SF Symbols 里没有能把「漫画」和「图书」
    /// 分开的符号，此前漫画用 `book.pages`、图书用 `text.book.closed`，两个都是书的形状，
    /// 用户在这一屏选类型时分不出哪个是哪个。`scriptSource` 不是生成 kind，没有对应徽章，
    /// 继续走系统符号。
    @ViewBuilder
    private func optionIcon(for kind: SourceImportOptionKind) -> some View {
        if let assetName: String = kind.badgeAssetName {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        } else {
            Image(systemName: kind.systemImageName)
        }
    }

    private func select(_ option: SourceImportOption) {
        switch option.kind {
        case .comicSource:
            self.isShowingComicGeneration = true
        case .videoSource:
            self.isShowingVideoGeneration = true
        case .bookSource:
            self.isShowingBookGeneration = true
        case .scriptSource:
            self.unavailableOption = option.kind
        }
    }

    private var unavailableOptionBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.unavailableOption != nil
            },
            set: { newValue in
                if newValue == false {
                    self.unavailableOption = nil
                }
            }
        )
    }

    private var unavailableOptionMessage: String {
        switch self.unavailableOption {
        case .comicSource:
            return "Comic sources can be added from the Comics source form."
        case .videoSource:
            return "Video sources can be added from the Video source form."
        case .bookSource:
            return "Book sources can be added from the Book source form."
        case .scriptSource:
            return "Script Source is closed. Use Website Rule JSON or URL-based source search instead."
        case nil:
            return "This source type is not available yet."
        }
    }
}

private extension SourceImportOptionKind {
    var displayTitle: String {
        switch self {
        case .comicSource:
            return NSLocalizedString("Comics", comment: "")
        case .videoSource:
            return NSLocalizedString("Video", comment: "")
        case .bookSource:
            return NSLocalizedString("Books", comment: "")
        case .scriptSource:
            return "Script Source"
        }
    }

    /// 中文注释：三种生成 kind 各有一枚圆形徽章资源（青蓝=视频、紫=漫画、金=图书），
    /// 颜色本身就是类型编码，因此不跟随 tintColor。没有徽章的 kind 返回 nil，回退到 `systemImageName`。
    var badgeAssetName: String? {
        switch self {
        case .comicSource:
            return "ComicKindBadge"
        case .videoSource:
            return "VideoKindBadge"
        case .bookSource:
            return "BookKindBadge"
        case .scriptSource:
            return nil
        }
    }

    var systemImageName: String {
        switch self {
        case .comicSource:
            return "book.pages"
        case .videoSource:
            return "play.rectangle"
        case .bookSource:
            return "text.book.closed"
        case .scriptSource:
            return "terminal"
        }
    }
}
