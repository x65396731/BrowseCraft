import AuthenticationServices
import Foundation
import UIKit

enum AppleSignInAuthorizationError: Error, Equatable, Sendable {
    case operationInFlight
    case cancelled
    case missingIdentityToken
    case invalidIdentityTokenEncoding
    case authorizationFailed
    case presentationUnavailable
}

@MainActor
protocol AppleSignInAuthorizing: AnyObject, Sendable {
    func authorize(nonce: String) async throws -> String
}

/// 中文注释：只负责原生 Apple 授权 UI；不读取 Apple user 字段，也不持久化 Identity Token。
@MainActor
final class AuthenticationServicesAppleSignInAuthorizer:
    NSObject,
    AppleSignInAuthorizing,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, any Error>?
    private var authorizationController: ASAuthorizationController?

    nonisolated override init() {
        super.init()
    }

    func authorize(nonce: String) async throws -> String {
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
        self.resume(returning: identityToken)
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

    private func resume(returning identityToken: String) {
        let continuation: CheckedContinuation<String, any Error>? = self.continuation
        self.continuation = nil
        self.authorizationController = nil
        continuation?.resume(returning: identityToken)
    }

    private func resume(throwing error: any Error) {
        let continuation: CheckedContinuation<String, any Error>? = self.continuation
        self.continuation = nil
        self.authorizationController = nil
        continuation?.resume(throwing: error)
    }
}
