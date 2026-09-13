import ReadiumNavigator
import ReadiumShared
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
            let navigator: EPUBNavigatorViewController = try EPUBNavigatorViewController(
                publication: self.publication,
                initialLocation: self.initialLocation,
                httpServer: ReadiumBookEnvironment.shared.httpServer
            )
            navigator.delegate = context.coordinator
            self.proxy.navigator = navigator
            return navigator
        } catch {
            self.onError(String(describing: error))
            return UIViewController()
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        private let onLocationChange: @MainActor (Locator) -> Void
        private let onError: @MainActor (String) -> Void

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
