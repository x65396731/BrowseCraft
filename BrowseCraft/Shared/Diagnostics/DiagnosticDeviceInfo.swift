import Foundation

// 中文注释：版本、构建号、机型与系统版本的唯一取值处：Crashlytics 全局键与问题报告的「环境」组同源
// （Analytics-Events-Design.md 第 6.2 节、Problem-Report-Design.md 第六节）。

enum DiagnosticDeviceInfo {
    static var appVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var buildNumber: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    static var systemVersion: String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }

    /// 中文注释：App 当前界面语言（主 bundle 的首选本地化），不是系统地区。
    static var interfaceLanguage: String {
        return Bundle.main.preferredLocalizations.first ?? "en"
    }

    static var deviceModel: String {
        var systemInfo: utsname = utsname()
        uname(&systemInfo)

        let mirror: Mirror = Mirror(reflecting: systemInfo.machine)
        let identifier: String = mirror.children.reduce(into: "") { result, element in
            guard let value: Int8 = element.value as? Int8, value != 0 else {
                return
            }
            result.append(String(UnicodeScalar(UInt8(value))))
        }

        return identifier.isEmpty ? "unknown" : identifier
    }
}
