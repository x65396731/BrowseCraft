import SwiftUI

// 中文注释：页面曝光的唯一入口（设计文档「设计原则 › 页面曝光」）。每个页面挂一次 `.analyticsScreen(.xxx)`：
// 页面每次显示（含从下级页返回、盖在上面的 sheet / 全屏页关闭后重新露出来）都设置 Crashlytics 的当前页面并报一次 `screen_view`。
// Firebase 的自动屏幕报告在 project.yml 的 Info.plist 属性里关掉，只留这里的手动上报。

extension View {
    func analyticsScreen(_ screen: DiagnosticScreen) -> some View {
        return self.modifier(AnalyticsScreenModifier(screen: screen))
    }

    /// 中文注释：给页面内容在异步加载后才知道自己是哪一页的场景用（书阅读器打开后才知道是有声书）。
    /// nil 期间页面已经占住可见页栈顶、但不报曝光；变成非 nil 时报一次。
    func analyticsScreen(resolving screen: DiagnosticScreen?) -> some View {
        return self.modifier(AnalyticsScreenModifier(screen: screen))
    }
}

private struct AnalyticsScreenModifier: ViewModifier {
    let screen: DiagnosticScreen?
    @State private var token: UUID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                AnalyticsScreenReporter.appeared(self.token, screen: self.screen)
            }
            .onDisappear {
                AnalyticsScreenReporter.disappeared(self.token)
            }
            .onChange(of: self.screen) { _, newValue in
                if let newValue {
                    AnalyticsScreenReporter.resolved(self.token, screen: newValue)
                }
            }
    }
}

/// 中文注释：可见页栈。SwiftUI 弹 sheet / fullScreenCover / 盖层时，下层页面既不 onDisappear 也不在关闭后 onAppear，
/// 只靠 onAppear 报曝光会让关掉 sheet 之后的事件一直挂在已关闭的页上。这里按 onAppear 入栈、onDisappear 出栈，
/// 栈顶页面消失时把重新露出来的下一层补报一次，不需要每个 `.sheet` 的宿主各自补报。
/// 导航压栈 / 出栈与切标签页时下层页面自己会 onAppear，栈顶出栈后先等一轮主线程，新页面已经报过就不再补报。
@MainActor
enum AnalyticsScreenReporter {
    private struct Entry {
        let token: UUID
        var screen: DiagnosticScreen?
    }

    private static var visible: [Entry] = []
    /// 最近一次报曝光的页面实例；补报前用它判断栈顶是否已经报过。
    private static var reportedToken: UUID?
    private static var isSettleScheduled: Bool = false

    fileprivate static func appeared(_ token: UUID, screen: DiagnosticScreen?) {
        self.visible.removeAll { $0.token == token }
        self.visible.append(Entry(token: token, screen: screen))
        if let screen {
            self.report(token, screen: screen)
        }
    }

    fileprivate static func resolved(_ token: UUID, screen: DiagnosticScreen) {
        guard let index: Int = self.visible.firstIndex(where: { $0.token == token }) else {
            return
        }
        self.visible[index].screen = screen
        self.report(token, screen: screen)
    }

    fileprivate static func disappeared(_ token: UUID) {
        guard let index: Int = self.visible.firstIndex(where: { $0.token == token }) else {
            return
        }
        let wasTop: Bool = index == self.visible.count - 1
        self.visible.remove(at: index)
        guard wasTop, self.isSettleScheduled == false else {
            return
        }
        // 中文注释：同一次转场里新页面的 onAppear 可能排在旧页面的 onDisappear 之后，等一轮再看栈顶。
        self.isSettleScheduled = true
        Task { @MainActor in
            self.settle()
        }
    }

    private static func settle() {
        self.isSettleScheduled = false
        guard let top: Entry = self.visible.last,
              top.token != self.reportedToken,
              let screen: DiagnosticScreen = top.screen else {
            return
        }
        self.report(top.token, screen: screen)
    }

    private static func report(_ token: UUID, screen: DiagnosticScreen) {
        self.reportedToken = token
        CrashDiagnostics.shared.setScreen(screen)
        AppAnalytics.shared.logScreenView(screen)
    }
}
