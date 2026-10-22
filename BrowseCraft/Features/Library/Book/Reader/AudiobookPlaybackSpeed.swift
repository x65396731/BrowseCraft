import Foundation

// 中文注释：有声书倍速（docs/design/Audiobook-Player-Page-Redesign-Design.md 裁定 6）：五档，全局记一个值，
// 存 UserDefaults，不进数据库、不同步 iCloud。引擎是 Readium `AudioNavigator.submitPreferences(AudioPreferences(speed:))`。

enum AudiobookPlaybackSpeed: Double, CaseIterable, Identifiable, Sendable {
    case slower = 0.75
    case normal = 1.0
    case faster = 1.25
    case fast = 1.5
    case fastest = 2.0

    static let defaultsKey: String = "audiobook.playbackSpeed"

    var id: Double {
        return self.rawValue
    }

    /// 胶囊与菜单上的写法：「0.75×」「1.0×」「1.25×」「1.5×」「2.0×」（数字不本地化，各语言同写）。
    var label: String {
        switch self {
        case .slower:
            return "0.75×"
        case .normal:
            return "1.0×"
        case .faster:
            return "1.25×"
        case .fast:
            return "1.5×"
        case .fastest:
            return "2.0×"
        }
    }

    /// 没存过或存的值不在五档里时为 1.0×。
    static func stored(in defaults: UserDefaults = .standard) -> AudiobookPlaybackSpeed {
        return AudiobookPlaybackSpeed(rawValue: defaults.double(forKey: Self.defaultsKey)) ?? .normal
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(self.rawValue, forKey: Self.defaultsKey)
    }
}
