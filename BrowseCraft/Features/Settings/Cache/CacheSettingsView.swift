import SwiftUI

// 中文注释：缓存页（`docs/design/Cache-Page-Redesign-Design.md`）：从设置页「同步与存储 › 缓存」推进来；
// 用量卡 + 封面与漫画页上限 + 清除缓存。上限、用量与清除的动作都由 `SettingsViewModel` 执行。
struct CacheSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CacheUsageCard(
                    usage: self.viewModel.imageCacheUsage,
                    coverLimitBytes: self.viewModel.imageCacheSettings.limitBytes
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)

                self.limitGroup

                self.clearSection
            }
            .padding(.bottom, 24)
        }
        .background(CatalogPalette.pageBackground)
        .navigationTitle(NSLocalizedString("Cache", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        // 中文注释：二级页隐藏底栏，左上返回是唯一出口（用户裁定，与 coin 记录页同一做法）。
        .toolbar(.hidden, for: .tabBar)
        .task {
            await self.viewModel.refreshImageCacheUsage()
        }
        .alert("Cache Settings", isPresented: self.cacheErrorAlertBinding) {
            Button("OK", role: .cancel) {
                self.viewModel.cacheErrorMessage = nil
            }
        } message: {
            Text(self.viewModel.cacheErrorMessage ?? "")
        }
    }

    // MARK: - 上限

    /// 中文注释：上限只管封面与漫画页；每档旁写两块合计最多占用，让数字对得上（用户裁定：两块分开计，只把显示写清楚）。
    private var limitGroup: some View {
        SettingsCardGroup(
            title: NSLocalizedString("cache_limit_section", comment: "封面与漫画页上限"),
            footer: NSLocalizedString("cache_limit_footer", comment: "上限只管哪块与自动清理说明")
        ) {
            ForEach(Array(ImageCacheSettings.availableLimits.enumerated()), id: \.element) { index, option in
                if index > 0 {
                    SettingsRowSeparator(leadingInset: 16)
                }
                self.limitRow(option)
            }
        }
    }

    private func limitRow(_ option: ImageCacheLimitOption) -> some View {
        let isSelected: Bool = option == self.viewModel.imageCacheSettings.limit
        let totalBytes: Int = option.bytes + ItemThumbnailLimit.bytes
        return Button(
            action: {
                guard isSelected == false else {
                    return
                }
                self.viewModel.selectImageCacheLimit(option)
                Task {
                    await self.viewModel.refreshImageCacheUsage()
                }
            },
            label: {
                HStack(spacing: 10) {
                    Text(option.displayTitle)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(String(
                        format: NSLocalizedString("cache_limit_total", comment: "共最多 %@"),
                        CacheByteFormatter.string(totalBytes)
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(CatalogPalette.settingsIcon)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
        )
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 清除

    /// 中文注释：不弹确认（用户裁定）；清除中换成转圈，清完显示释放了多少约 3 秒，下方写明不删什么。
    private var clearSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(
                action: {
                    Task {
                        await self.viewModel.clearImageCache()
                    }
                },
                label: {
                    HStack(spacing: 8) {
                        if self.viewModel.isClearingCache {
                            ProgressView()
                            Text(NSLocalizedString("cache_clearing", comment: "正在清除"))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(NSLocalizedString("Clear Cache", comment: ""))
                                .foregroundStyle(CatalogPalette.destructive)
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            )
            .buttonStyle(.plain)
            .disabled(self.viewModel.isClearingCache)
            .padding(.horizontal, 20)
            .padding(.top, 24)

            if let freedBytes: Int = self.viewModel.lastClearedBytes {
                Label(
                    String(
                        format: NSLocalizedString("cache_cleared_freed", comment: "已清除，释放 %@"),
                        CacheByteFormatter.string(freedBytes)
                    ),
                    systemImage: "checkmark"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CatalogPalette.gain)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .transition(.opacity)
            }

            Text(NSLocalizedString("cache_clear_keeps", comment: "清除不删除的内容"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
        .animation(.easeInOut(duration: 0.2), value: self.viewModel.lastClearedBytes)
    }

    private var cacheErrorAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.cacheErrorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.cacheErrorMessage = nil
                }
            }
        )
    }
}

/// 中文注释：列表缩略图的固定上限；用量算好前也要能显示「共最多」，取不到实测值时用这个。
private enum ItemThumbnailLimit {
    static let bytes: Int = 256 * 1024 * 1024
}

/// 中文注释：与档位同一口径（1 MB = 1024 × 1024 字节），512 MB 档显示「512 MB」、合计 1280 MB 显示「1.25 GB」。
enum CacheByteFormatter {
    static func string(_ bytes: Int) -> String {
        let formatter: ByteCountFormatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// 用量卡：两块图片缓存的合计与各自的已用 / 上限；用量算好前显示「正在计算」。
private struct CacheUsageCard: View {
    let usage: ImageCacheUsage?
    let coverLimitBytes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("cache_usage_title", comment: "图片缓存已用"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let usage: ImageCacheUsage = self.usage {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: CacheByteFormatter.string(usage.totalBytes))
                            .font(.title.weight(.heavy))
                            .monospacedDigit()
                        Text(String(
                            format: NSLocalizedString("cache_usage_max", comment: "/ 最多 %@"),
                            CacheByteFormatter.string(self.coverLimitBytes + self.thumbnailLimitBytes)
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(NSLocalizedString("cache_calculating", comment: "正在计算"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 38)
                }
            }
            .accessibilityElement(children: .combine)

            CacheUsageBar(
                title: NSLocalizedString("cache_usage_covers", comment: "封面与漫画页"),
                usedBytes: self.usage?.coverBytes,
                limitBytes: self.coverLimitBytes,
                isFixed: false
            )
            CacheUsageBar(
                title: NSLocalizedString("cache_usage_thumbnails", comment: "列表缩略图"),
                usedBytes: self.usage?.thumbnailBytes,
                limitBytes: self.thumbnailLimitBytes,
                isFixed: true
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var thumbnailLimitBytes: Int {
        guard let limit: Int = self.usage?.thumbnailLimitBytes, limit > 0 else {
            return ItemThumbnailLimit.bytes
        }
        return limit
    }
}

/// 一条用量：左名称、右「已用 / 上限」（固定上限后缀「· 固定」），下方 6pt 进度条；与来源页的用量条同一做法。
private struct CacheUsageBar: View {
    let title: String
    let usedBytes: Int?
    let limitBytes: Int
    let isFixed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.title)
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text(verbatim: self.valueText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CatalogPalette.fillBackground)
                    Capsule()
                        .fill(CatalogPalette.addAction)
                        .frame(width: proxy.size.width * self.fraction)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var valueText: String {
        let used: String = self.usedBytes.map(CacheByteFormatter.string) ?? "—"
        let value: String = "\(used) / \(CacheByteFormatter.string(self.limitBytes))"
        guard self.isFixed else {
            return value
        }
        return "\(value) · \(NSLocalizedString("cache_usage_fixed", comment: "固定"))"
    }

    private var fraction: CGFloat {
        guard let used: Int = self.usedBytes, self.limitBytes > 0 else {
            return 0
        }
        return min(1, CGFloat(used) / CGFloat(self.limitBytes))
    }
}
