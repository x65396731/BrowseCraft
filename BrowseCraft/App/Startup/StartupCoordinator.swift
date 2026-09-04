import Observation
import Combine
import Foundation

// 中文注释：StartupCoordinator 只协调启动状态、超时和跳过，不负责渲染或控制视频循环。

@MainActor
@Observable
final class StartupCoordinator {
    struct Dependencies {
        let hasSources: @MainActor @Sendable () async throws -> Bool
        let loadSelectedSource: @MainActor @Sendable () async -> LibraryInitialLoadOutcome
    }

    private(set) var phase: StartupPhase = .checkingSources

    private let policy: StartupPolicy
    private let dependencies: Dependencies
    /// 中文注释：任务句柄不是界面状态，且 deinit 需要直接触碰存储属性——排除观察。
    @ObservationIgnored
    private var sourceCheckTask: Task<Void, Never>?
    /// 中文注释：任务句柄不是界面状态，且 deinit 需要直接触碰存储属性——排除观察。
    @ObservationIgnored
    private var timeoutTask: Task<Void, Never>?
    /// 中文注释：任务句柄不是界面状态，且 deinit 需要直接触碰存储属性——排除观察。
    @ObservationIgnored
    private var sourceLoadTask: Task<Void, Never>?
    private var hasStarted: Bool = false
    private var didVideoPlaybackFail: Bool = false

    init(
        policy: StartupPolicy = StartupPolicy(),
        dependencies: Dependencies
    ) {
        self.policy = policy
        self.dependencies = dependencies
    }

    deinit {
        self.sourceCheckTask?.cancel()
        self.timeoutTask?.cancel()
        self.sourceLoadTask?.cancel()
    }

    /// 中文注释：启动只执行一次；本地无源时立即解锁，有源时并行开始加载与超时计时。
    func start() {
        guard self.hasStarted == false else {
            return
        }

        self.hasStarted = true

        let hasSources: @MainActor @Sendable () async throws -> Bool = self.dependencies.hasSources
        self.sourceCheckTask = Task { [weak self] in
            do {
                guard try await hasSources() else {
                    self?.sourceCheckTask = nil
                    self?.phase = .noSources
                    return
                }

                guard Task.isCancelled == false else {
                    return
                }

                self?.sourceCheckTask = nil
                if self?.didVideoPlaybackFail == true {
                    self?.phase = .videoPlaybackFailed(destination: .library)
                } else {
                    self?.phase = .loadingSource
                    self?.startTimeout()
                }
                self?.startSourceLoad()
            } catch is CancellationError {
                return
            } catch {
                self?.sourceCheckTask = nil
                self?.phase = .sourceCheckFailed
            }
        }
    }

    /// 中文注释：只有用户主动调用 skip 才会关闭启动层；超时本身绝不会让动画消失。
    @discardableResult
    func skip() -> StartupDestination? {
        guard case .unlocked(_, let destination) = self.phase else {
            return nil
        }

        self.stopTimeout()
        self.phase = .dismissed(destination: destination)
        return destination
    }

    /// 中文注释：播放器失败时解锁跳过；若本地源检查尚未完成，则等待目标页确定后再解锁。
    func reportVideoPlaybackFailure() {
        self.didVideoPlaybackFail = true

        guard self.phase == .loadingSource else {
            return
        }

        self.stopTimeout()
        self.phase = .videoPlaybackFailed(destination: .library)
    }

    private func startTimeout() {
        self.stopTimeout()
        let timeout: Duration = self.policy.sourceLoadTimeout

        self.timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }

            guard Task.isCancelled == false else {
                return
            }

            self?.unlockAfterTimeoutIfNeeded()
        }
    }

    private func startSourceLoad() {
        let loadSelectedSource: @MainActor @Sendable () async -> LibraryInitialLoadOutcome = self.dependencies.loadSelectedSource

        self.sourceLoadTask = Task { [weak self] in
            let outcome: LibraryInitialLoadOutcome = await loadSelectedSource()
            guard Task.isCancelled == false else {
                self?.handleSourceLoadOutcome(.cancelled)
                return
            }

            self?.handleSourceLoadOutcome(outcome)
        }
    }

    private func unlockAfterTimeoutIfNeeded() {
        guard self.phase == .loadingSource else {
            return
        }

        self.timeoutTask = nil
        // 中文注释：这里只解锁按钮；播放器继续循环，sourceLoadTask 继续在后台执行。
        self.phase = .sourceLoadTimedOut
    }

    private func handleSourceLoadOutcome(_ outcome: LibraryInitialLoadOutcome) {
        self.sourceLoadTask = nil

        guard self.phase == .loadingSource else {
            // 中文注释：超时、视频失败或用户已跳过后，加载结果留在共享 LibraryViewModel 中，不覆盖启动状态。
            return
        }

        switch outcome {
        case .noSources:
            self.stopTimeout()
            self.phase = .noSources
        case .loaded:
            self.stopTimeout()
            self.phase = .sourceLoaded
        case .failed:
            self.stopTimeout()
            self.phase = .sourceLoadFailed
        case .cancelled:
            // 中文注释：取消不是失败，继续等待独立的 15 秒计时解锁跳过。
            break
        }
    }

    private func stopTimeout() {
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
    }
}
