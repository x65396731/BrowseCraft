import Foundation

// 中文注释：启动合同只描述 App 内启动动画的状态与跳转语义，不拥有播放器或源加载实现。

/// 中文注释：启动动画关闭后需要展示的根标签页。
enum StartupDestination: Equatable {
    case sources
    case library
}

/// 中文注释：记录跳过按钮被解锁的原因，便于界面文案、诊断和后续分析保持一致。
enum StartupUnlockReason: Equatable {
    case noSources
    case sourceCheckFailed
    case sourceLoaded
    case sourceLoadFailed
    case sourceLoadTimedOut
    case videoPlaybackFailed
}

/// 中文注释：启动流程使用单一枚举表达互斥状态，避免多个布尔值组合出非法状态。
enum StartupPhase: Equatable {
    case checkingSources
    case loadingSource
    case unlocked(reason: StartupUnlockReason, destination: StartupDestination)
    case dismissed(destination: StartupDestination)

    /// 中文注释：只有已经确定目标页并解锁时才允许用户跳过启动动画。
    var canSkip: Bool {
        guard case .unlocked = self else {
            return false
        }

        return true
    }

    /// 中文注释：checking/loading 阶段尚未确定可执行跳转，因此不暴露目标页。
    var destination: StartupDestination? {
        switch self {
        case .checkingSources, .loadingSource:
            return nil
        case .unlocked(_, let destination), .dismissed(let destination):
            return destination
        }
    }

    var isDismissed: Bool {
        guard case .dismissed = self else {
            return false
        }

        return true
    }

    /// 中文注释：无源是本地可立即确认的状态，跳过后进入 Sources。
    static var noSources: StartupPhase {
        return .unlocked(reason: .noSources, destination: .sources)
    }

    /// 中文注释：本地源列表读取失败时仍允许进入 Sources，由现有错误入口承接恢复操作。
    static var sourceCheckFailed: StartupPhase {
        return .unlocked(reason: .sourceCheckFailed, destination: .sources)
    }

    /// 中文注释：有源加载成功后进入 Library。
    static var sourceLoaded: StartupPhase {
        return .unlocked(reason: .sourceLoaded, destination: .library)
    }

    /// 中文注释：有源加载失败不阻塞进入 App，错误继续由 Library 展示。
    static var sourceLoadFailed: StartupPhase {
        return .unlocked(reason: .sourceLoadFailed, destination: .library)
    }

    /// 中文注释：超时只解锁跳过，不代表取消仍在后台执行的源加载任务。
    static var sourceLoadTimedOut: StartupPhase {
        return .unlocked(reason: .sourceLoadTimedOut, destination: .library)
    }

    /// 中文注释：视频失败时沿用已经通过本地源检查确定的目标页。
    static func videoPlaybackFailed(destination: StartupDestination) -> StartupPhase {
        return .unlocked(reason: .videoPlaybackFailed, destination: destination)
    }
}

/// 中文注释：启动策略集中保存时间合同，计时实现将在 StartupCoordinator 中使用单调时钟。
struct StartupPolicy: Equatable {
    let sourceLoadTimeout: Duration

    init(sourceLoadTimeout: Duration = .seconds(15)) {
        self.sourceLoadTimeout = sourceLoadTimeout
    }
}
