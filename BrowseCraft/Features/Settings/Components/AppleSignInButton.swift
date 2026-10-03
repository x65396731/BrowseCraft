import AuthenticationServices
import SwiftUI

/// 系统「通过 Apple 登录」按钮（`docs/design/Settings-Page-Redesign-Design.md` 3.2）。
///
/// 中文注释：Apple 对这个按钮的外观有要求，所以不自绘；这里只借它的外观，点按回调 `action`，
/// 授权流程仍由 `SettingsViewModel.togglePortalAccount` 经身份端口发起，与原来的登录行同一条路径。
/// 按钮样式在创建时定下，深浅色切换要靠调用方给它换 `id` 重建。
struct AppleSignInButton: UIViewRepresentable {
    let style: ASAuthorizationAppleIDButton.Style
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(action: self.action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button: ASAuthorizationAppleIDButton = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: self.style
        )
        button.cornerRadius = 22
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleTap),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = self.action
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func handleTap() {
            self.action()
        }
    }
}
