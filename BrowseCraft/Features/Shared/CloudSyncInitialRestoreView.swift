import SwiftUI

/// iCloud 首次恢复的卡片，来源页与收藏页共用（`docs/design/Sources-Page-Redesign-Design.md` 2.7）。
///
/// 中文注释：只画卡片本身，摆放由宿主决定。失败时不放重试按钮，改为提示「下拉可重试」——
/// 宿主必须让这一屏真的拉得动，并在下拉时调用 `CloudSyncSettingsViewModel.retryInitialRestoreIfFailed()`。
/// 卡片里没有可点的控件，宿主把它叠在列表上时可以关掉命中测试，让拖拽落到下面的列表。
@MainActor
struct CloudSyncInitialRestoreView: View {
    let state: CloudSyncInitialRestoreState

    var body: some View {
        switch self.state {
        case .waitingForCloud:
            self.progressCard(
                systemImage: "icloud",
                title: NSLocalizedString("Waiting for iCloud", comment: ""),
                message: NSLocalizedString("Your sources and favorites will appear after iCloud becomes available.", comment: "")
            )

        case .restoring:
            self.progressCard(
                systemImage: "icloud.and.arrow.down",
                title: NSLocalizedString("Restoring from iCloud", comment: ""),
                message: NSLocalizedString("Downloading and merging your saved data.", comment: "")
            )

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(NSLocalizedString("iCloud Restore Failed", comment: ""), systemImage: "exclamationmark.icloud")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(CatalogPalette.warning)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(NSLocalizedString("cloud_restore_pull_to_retry", comment: ""), systemImage: "arrow.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(CatalogPalette.warning.opacity(0.3), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)

        case .notRequired, .restored:
            EmptyView()
        }
    }

    private func progressCard(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(CatalogPalette.addAction)
                .frame(width: 56, height: 56)
                .background(CatalogPalette.addAction.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView()
                .tint(CatalogPalette.addAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
