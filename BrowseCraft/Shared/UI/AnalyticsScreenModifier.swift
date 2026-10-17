import SwiftUI

// 中文注释：页面曝光的唯一入口（设计文档「设计原则 › 页面曝光」）。每个页面挂一次 `.analyticsScreen(.xxx)`：
// 页面每次显示（含从下级页返回）都设置 Crashlytics 的当前页面并报一次 `screen_view`，取代原来各处成对的两行调用。
// Firebase 的自动屏幕报告在 project.yml 的 Info.plist 属性里关掉，只留这里的手动上报。

extension View {
    func analyticsScreen(_ screen: DiagnosticScreen) -> some View {
        return self.onAppear {
            AnalyticsScreenReporter.report(screen)
        }
    }
}

/// 中文注释：给拿不到 onAppear 的场景用（例如页面内容在异步加载后才知道自己是哪一页：书阅读器打开后才知道是有声书）。
enum AnalyticsScreenReporter {
    static func report(_ screen: DiagnosticScreen) {
        CrashDiagnostics.shared.setScreen(screen)
        AppAnalytics.shared.logScreenView(screen)
    }
}
