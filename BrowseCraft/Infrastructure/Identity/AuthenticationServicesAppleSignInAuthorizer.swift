import AuthenticationServices
import Foundation
import UIKit

/// 中文注释：只负责原生 Apple 授权 UI；交回 identityToken、authorizationCode 与 Apple user 标识，自己不持久化任何一样。
@MainActor
final class AuthenticationServicesAppleSignInAuthorizer:
    NSObject,
    AppleSignInAuthorizing,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleSignInAuthorization, any Error>?
    private var authorizationController: ASAuthorizationController?

    nonisolated override init() {
        super.init()
    }

    func authorize(nonce: String) async throws -> AppleSignInAuthorization {
        guard Task.isCancelled == false else {
            throw AppleSignInAuthorizationError.cancelled
        }
        guard self.continuation == nil else {
            throw AppleSignInAuthorizationError.operationInFlight
        }
        guard self.currentPresentationAnchor != nil else {
            throw AppleSignInAuthorizationError.presentationUnavailable
        }

        return try await withTaskCancellationHandler {
            guard Task.isCancelled == false else {
                throw AppleSignInAuthorizationError.cancelled
            }
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let request: ASAuthorizationAppleIDRequest =
                    ASAuthorizationAppleIDProvider().createRequest()
                request.nonce = nonce

                let controller: ASAuthorizationController = ASAuthorizationController(
                    authorizationRequests: [request]
                )
                self.authorizationController = controller
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resume(throwing: AppleSignInAuthorizationError.cancelled)
            }
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard controller === self.authorizationController else {
            return
        }
        guard let credential: ASAuthorizationAppleIDCredential =
                authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData: Data = credential.identityToken else {
            self.resume(throwing: AppleSignInAuthorizationError.missingIdentityToken)
            return
        }
        guard let identityToken: String = String(
            data: identityTokenData,
            encoding: .utf8
        ), identityToken.isEmpty == false else {
            self.resume(
                throwing: AppleSignInAuthorizationError.invalidIdentityTokenEncoding
            )
            return
        }
        guard let authorizationCodeData: Data = credential.authorizationCode,
              let authorizationCode: String = String(
                data: authorizationCodeData,
                encoding: .utf8
              ), authorizationCode.isEmpty == false else {
            self.resume(throwing: AppleSignInAuthorizationError.missingAuthorizationCode)
            return
        }
        self.resume(
            returning: AppleSignInAuthorization(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: credential.user
            )
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        guard controller === self.authorizationController else {
            return
        }
        if let authorizationError: ASAuthorizationError =
            error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            self.resume(throwing: AppleSignInAuthorizationError.cancelled)
            return
        }
        self.resume(throwing: AppleSignInAuthorizationError.authorizationFailed)
    }

    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        return self.currentPresentationAnchor ?? UIWindow(frame: .zero)
    }

    private var currentPresentationAnchor: ASPresentationAnchor? {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes
            .compactMap { scene in
                return scene as? UIWindowScene
            }
        if let keyWindow: UIWindow = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let window: UIWindow = scenes.flatMap(\.windows).first {
            return window
        }
        return nil
    }

    private func resume(returning authorization: AppleSignInAuthorization) {
        let continuation: CheckedContinuation<AppleSignInAuthorization, any Error>? = self.continuation
        self.continuation = nil
        self.authorizationController = nil
        continuation?.resume(returning: authorization)
    }

    private func resume(throwing error: any Error) {
        let continuation: CheckedContinuation<AppleSignInAuthorization, any Error>? = self.continuation
        self.continuation = nil
        self.authorizationController = nil
        continuation?.resume(throwing: error)
    }
}
