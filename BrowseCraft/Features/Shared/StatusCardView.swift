import SwiftUI

// 中文注释：状态卡——56pt 圆形图标 + 标题 + 一句说明，圆角 22。云同步页的状态卡与网址输入页的结论卡、结果卡共用
// （`docs/design/Cloud-Sync-Page-Redesign-Design.md` 第三节、`docs/design/Generation-Input-Page-Redesign-Design.md` 第三节）。
// 正常用设置页图标蓝，异常用警示色并加描边，中性用次级灰；不用绿、不用红。

enum StatusCardTone {
    case action
    case warning
    case neutral
}

struct StatusCardView<Accessory: View>: View {
    let systemImage: String
    let title: String
    let message: String
    var tone: StatusCardTone = .action
    /// 进行中：说明下面一个转圈。
    var isInProgress: Bool = false
    /// 说明下面的附加内容（小字、链接），没有就传 `EmptyView`。
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: self.systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(self.tint)
                .frame(width: 56, height: 56)
                .background(self.tintFill, in: Circle())
                .accessibilityHidden(true)
            Text(self.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(self.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            self.accessory
            if self.isInProgress {
                ProgressView()
                    .tint(CatalogPalette.settingsIcon)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CatalogPalette.warning.opacity(self.tone == .warning ? 0.3 : 0), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch self.tone {
        case .action:
            return CatalogPalette.settingsIcon
        case .warning:
            return CatalogPalette.warning
        case .neutral:
            return .secondary
        }
    }

    private var tintFill: Color {
        switch self.tone {
        case .action:
            return CatalogPalette.settingsIconFill
        case .warning:
            return CatalogPalette.warningFill
        case .neutral:
            return CatalogPalette.fillBackground
        }
    }
}

extension StatusCardView where Accessory == EmptyView {
    init(
        systemImage: String,
        title: String,
        message: String,
        tone: StatusCardTone = .action,
        isInProgress: Bool = false
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            message: message,
            tone: tone,
            isInProgress: isInProgress,
            accessory: { EmptyView() }
        )
    }
}
