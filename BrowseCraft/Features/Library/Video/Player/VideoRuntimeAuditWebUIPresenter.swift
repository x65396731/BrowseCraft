import BrowseCraftCore
import SwiftUI

// 中文注释：BC-EVIDENCE-077.1/.5——显式 runtime audit 的前台 WebUI 承载者。
// 它用**同一个** VideoWebPlayerView / VideoWebPlayerRequest(reference:requestConfig:) 在根视图
// 之上展示 WebUI 路线，等待 playing 观察，结束即关闭；一次只承载一个 session。
@MainActor
final class VideoRuntimeAuditWebUIPresenter: ObservableObject, VideoRuntimeAuditWebUIObserving {
    struct ActiveSession: Identifiable {
        let id: String
        let request: VideoWebPlayerRequest
        let handler: VideoRuntimeAuditMediaEventHandler
    }

    /// 中文注释：首个绑定候选元素 playing 之后再等一小段，捕捉同 session 的第二个媒体元素（广告 + 正片）。
    static let settleInterval: TimeInterval = 3

    @Published private(set) var activeSession: ActiveSession?

    func observe(
        reference: SourceVideoPlaybackReference,
        requestConfig: SourcePlaybackRequestConfig?,
        sessionToken: String,
        timeout: TimeInterval,
        activationSelector: String?
    ) async -> VideoRuntimeAuditWebUIObservation {
        guard self.activeSession == nil else {
            return VideoRuntimeAuditWebUIBindingReducer.reduce(events: [], timedOut: false)
        }
        let handler: VideoRuntimeAuditMediaEventHandler = VideoRuntimeAuditMediaEventHandler(
            sessionToken: sessionToken,
            activationSelector: activationSelector
        )
        self.activeSession = ActiveSession(
            id: sessionToken,
            request: VideoWebPlayerRequest(
                reference: reference,
                requestConfig: requestConfig
            ),
            handler: handler
        )
        defer {
            handler.detach()
            self.activeSession = nil
        }
        let timedOut: Bool = await handler.waitForFirstBindingCandidatePlaying(timeout: timeout)
        if timedOut == false {
            try? await Task.sleep(
                nanoseconds: UInt64(Self.settleInterval * 1_000_000_000)
            )
        }
        return VideoRuntimeAuditWebUIBindingReducer.reduce(
            events: handler.events,
            timedOut: timedOut,
            activation: handler.activation
        )
    }

    /// 中文注释：用户手动关闭覆盖层——按已观察到的事件如实归约，不视为通过。
    func cancelActiveSession() {
        self.activeSession?.handler.detach()
    }
}

/// 中文注释：根视图之上的 audit 覆盖层；无 active session 时不渲染任何东西。
struct VideoRuntimeAuditWebUIOverlay: View {
    @ObservedObject var presenter: VideoRuntimeAuditWebUIPresenter

    var body: some View {
        if let session: VideoRuntimeAuditWebUIPresenter.ActiveSession = self.presenter.activeSession {
            VideoWebPlayerView(
                request: session.request,
                title: "Runtime audit",
                auditMediaEventHandler: session.handler,
                controls: {
                    EmptyView()
                },
                onClose: {
                    self.presenter.cancelActiveSession()
                }
            )
            .id(session.id)
        }
    }
}
