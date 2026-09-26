@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
import SwiftUI
import UIKit

// 中文注释：EPUBNavigatorRepresentable 承载 Readium 的 EPUBNavigatorViewController；位置变化回给 VM。

struct EPUBNavigatorRepresentable: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocation: Locator?
    let proxy: BookNavigatorProxy
    let onLocationChange: @MainActor (Locator) -> Void
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(onLocationChange: self.onLocationChange, onError: self.onError)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        do {
            // 中文注释：Readium 3.x 的 EPUB Navigator 不再需要本地 HTTP 服务，资源由 Publication 直接供给。
            let colorScheme: ColorScheme = context.environment.colorScheme
            let navigator: EPUBNavigatorViewController = try EPUBNavigatorViewController(
                publication: self.publication,
                initialLocation: self.initialLocation,
                config: EPUBNavigatorViewController.Configuration(
                    preferences: Self.preferences(for: colorScheme)
                )
            )
            context.coordinator.appliedColorScheme = colorScheme
            navigator.delegate = context.coordinator
            self.proxy.navigator = navigator
            return navigator
        } catch {
            self.onError(String(describing: error))
            return UIViewController()
        }
    }

    /// 中文注释：阅读中切换系统深浅色时同步切换 Readium 主题；只在外观真的变了才提交，
    /// 避免每次 SwiftUI 刷新都让 Readium 重排版。
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let colorScheme: ColorScheme = context.environment.colorScheme
        guard let navigator: EPUBNavigatorViewController = uiViewController as? EPUBNavigatorViewController,
              context.coordinator.appliedColorScheme != colorScheme else {
            return
        }
        navigator.submitPreferences(Self.preferences(for: colorScheme))
        context.coordinator.appliedColorScheme = colorScheme
    }

    /// 中文注释：正文主题跟随系统外观。此前没传偏好，Readium 固定用浅色主题，深色模式下整页白底。
    private static func preferences(for colorScheme: ColorScheme) -> EPUBPreferences {
        return EPUBPreferences(theme: colorScheme == .dark ? .dark : .light)
    }

    @MainActor
    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        private let onLocationChange: @MainActor (Locator) -> Void
        private let onError: @MainActor (String) -> Void
        var appliedColorScheme: ColorScheme?

        init(onLocationChange: @escaping @MainActor (Locator) -> Void, onError: @escaping @MainActor (String) -> Void) {
            self.onLocationChange = onLocationChange
            self.onError = onError
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            self.onLocationChange(locator)
        }

        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            self.onError(String(describing: error))
        }

        func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
            UIApplication.shared.open(url)
        }
    }
}
