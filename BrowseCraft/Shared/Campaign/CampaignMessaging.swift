import BrowseCraftLog
import FirebaseInAppMessaging
import Foundation

/// 活动类提示的唯一出口（docs/design/Campaign-And-Rate-Notices-Design.md 第五节，`BCA-UI-004`）。
///
/// 中文注释：活动弹窗与新注册欢迎页的界面、插画与文案都在 Firebase 控制台制作，由 In-App Messaging 的默认显示组件呈现；
/// App 只做两件事——链接 SDK（`FirebaseApp.configure()` 之后它自己拉取并在打开 App 时显示活动弹窗），以及在约定的时机触发事件。
/// 这里不得替换显示组件，也不得为活动自绘弹窗、横幅或卡片。「传送使用统计」关闭时照常拉取与显示，只是 SDK 的展示与点击事件不报
/// （`BCA-OBS-005`）；「活动推送」开关不影响这里。
enum CampaignMessaging {
    /// 控制台里欢迎页那条消息的自定义触发事件名。
    static let welcomeNewAccountEvent: String = "welcome_new_account"

    /// 新注册且拿到赠送、Apple 登录面板收起后调用一次。`triggerEvent` 只在本机触发弹窗，不是 Analytics 事件。
    @MainActor
    static func triggerNewAccountWelcome() {
        InAppMessaging.inAppMessaging().triggerEvent(Self.welcomeNewAccountEvent)
        AppLog.notice(.app, "in-app-message-event-triggered", ["event": .code(Self.welcomeNewAccountEvent)])
    }
}
