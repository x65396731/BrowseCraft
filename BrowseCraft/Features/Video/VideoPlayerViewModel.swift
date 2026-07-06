import Foundation
import BrowseCraftCore

// 中文注释：VideoPlayerViewModel 管理单集播放历史的初始保存、自动保存和退出保存。
@MainActor
final class VideoPlayerViewModel: ObservableObject {
    @Published private(set) var currentPlaybackTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval?
    @Published private(set) var isPrepared: Bool = false
    @Published var errorMessage: String?

    let source: Source
    let reference: SourceVideoPlaybackReference
    let videoTitle: String
    let detailURL: URL?
    let coverURL: URL?

    private let saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase
    private let loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase
    private let userID: String
    private let now: () -> Date
    private var autosaveTask: Task<Void, Never>?
    private var didSeekToRestoredTime: Bool = false
    private var lastSavedPlaybackTime: TimeInterval?

    init(
        source: Source,
        reference: SourceVideoPlaybackReference,
        videoTitle: String,
        detailURL: URL?,
        coverURL: URL?,
        saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase,
        loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.reference = reference
        self.videoTitle = videoTitle
        self.detailURL = detailURL
        self.coverURL = coverURL
        self.saveVideoWatchHistoryUseCase = saveVideoWatchHistoryUseCase
        self.loadVideoWatchHistoryUseCase = loadVideoWatchHistoryUseCase
        self.userID = userID
        self.now = now
    }

    deinit {
        self.autosaveTask?.cancel()
    }

    var displayTitle: String {
        guard let episodeTitle: String = self.reference.episodeTitle,
              episodeTitle.isEmpty == false,
              episodeTitle != self.videoTitle else {
            return self.videoTitle
        }

        return "\(self.videoTitle) - \(episodeTitle)"
    }

    var nativeMediaURL: URL? {
        guard self.reference.status == .playable else {
            return nil
        }

        switch self.reference.candidateMediaKind {
        case .m3u8, .mp4:
            return self.reference.candidateMediaURL
        case .iframe, .unknown:
            return nil
        }
    }

    var fallbackPageURL: URL {
        return self.reference.playPageURL
    }

    var restoredPlaybackTime: TimeInterval {
        return self.currentPlaybackTime
    }

    func prepareForPlayback() {
        if self.isPrepared {
            return
        }

        self.isPrepared = true

        do {
            if let history: VideoWatchHistory = try self.loadVideoWatchHistoryUseCase.execute(
                userID: self.userID,
                sourceID: self.source.id,
                vodID: self.reference.vodID,
                sourceIndex: self.reference.sourceIndex,
                episodeIndex: self.reference.episodeIndex
            ) {
                self.currentPlaybackTime = history.lastPlaybackTime
                self.duration = history.duration
            }

            self.saveCurrentProgress(force: true)
        } catch {
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    func recordPlaybackProgress(currentTime: TimeInterval, totalTime: TimeInterval) {
        guard currentTime.isFinite,
              totalTime.isFinite else {
            return
        }

        self.currentPlaybackTime = max(0, currentTime)
        if totalTime > 0 {
            self.duration = totalTime
        }
        self.startAutosaveIfNeeded()
    }

    func markReadyToPlay(seek: (TimeInterval) -> Void) {
        guard self.didSeekToRestoredTime == false,
              self.restoredPlaybackTime > 1 else {
            return
        }

        self.didSeekToRestoredTime = true
        seek(self.restoredPlaybackTime)
    }

    func saveOnDisappear() {
        self.autosaveTask?.cancel()
        self.autosaveTask = nil
        self.saveCurrentProgress(force: true)
    }

    private func startAutosaveIfNeeded() {
        guard self.autosaveTask == nil else {
            return
        }

        self.autosaveTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await self?.saveCurrentProgress(force: false)
            }
        }
    }

    private func saveCurrentProgress(force: Bool) {
        if force == false,
           let lastSavedPlaybackTime: TimeInterval = self.lastSavedPlaybackTime,
           abs(lastSavedPlaybackTime - self.currentPlaybackTime) < 1 {
            return
        }

        do {
            try self.saveVideoWatchHistoryUseCase.execute(
                userID: self.userID,
                source: self.source,
                reference: self.reference,
                videoTitle: self.videoTitle,
                detailURL: self.detailURL,
                coverURL: self.coverURL,
                lastPlaybackTime: self.currentPlaybackTime,
                duration: self.duration,
                visitedAt: self.now()
            )
            self.lastSavedPlaybackTime = self.currentPlaybackTime
        } catch {
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }
}
