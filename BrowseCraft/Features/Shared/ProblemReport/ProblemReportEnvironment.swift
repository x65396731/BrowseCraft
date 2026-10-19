import SwiftUI

// 中文注释：报告面板从环境里取发送用例（Problem-Report-Design.md 第七节），由根视图注入；
// 库页与三种详情页不必各自接线。未注入时（预览、测试）面板不显示入口。

private struct ProblemReportSubmitterKey: EnvironmentKey {
    static let defaultValue: SubmitProblemReportUseCase? = nil
}

extension EnvironmentValues {
    var problemReportSubmitter: SubmitProblemReportUseCase? {
        get { self[ProblemReportSubmitterKey.self] }
        set { self[ProblemReportSubmitterKey.self] = newValue }
    }
}
