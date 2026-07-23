import StoreKit
import SwiftUI

// 中文注释：AppReviewRequestModifier 统一连接内容成功信号、本地资格策略和系统评分请求。
@MainActor
struct AppReviewRequestModifier: ViewModifier {
    private static let requestDelay: Duration = .seconds(2)

    let isContentSuccessfullyOpen: Bool
    let policy: AppReviewPromptPolicy

    @Environment(\.requestReview) private var requestReview
    @State private var hasRecordedSuccessfulOpen: Bool = false

    func body(content: Content) -> some View {
        content
            .task(id: self.isContentSuccessfullyOpen) {
                guard self.isContentSuccessfullyOpen,
                      self.hasRecordedSuccessfulOpen == false else {
                    return
                }

                self.hasRecordedSuccessfulOpen = true
                guard self.policy.recordSuccessfulContentOpen() else {
                    return
                }

                do {
                    try await Task.sleep(for: Self.requestDelay)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }

                guard Task.isCancelled == false,
                      self.policy.consumeReviewRequestEligibility() else {
                    return
                }

                self.requestReview()
            }
    }
}

extension View {
    @MainActor
    func requestsAppReviewAfterSuccessfulContentOpen(
        when isContentSuccessfullyOpen: Bool,
        policy: AppReviewPromptPolicy = .shared
    ) -> some View {
        return self.modifier(
            AppReviewRequestModifier(
                isContentSuccessfullyOpen: isContentSuccessfullyOpen,
                policy: policy
            )
        )
    }
}
