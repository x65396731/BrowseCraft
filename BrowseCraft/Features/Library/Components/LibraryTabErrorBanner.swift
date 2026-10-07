import SwiftUI

/// 有内容但当前分类报错时网格上方的横幅：警示色淡底、圆角 16（`docs/design/Library-Video-Page-Redesign-Design.md` 第七节）。
struct LibraryTabErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CatalogPalette.warning)
                .accessibilityHidden(true)

            Text(self.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatalogPalette.warningFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
