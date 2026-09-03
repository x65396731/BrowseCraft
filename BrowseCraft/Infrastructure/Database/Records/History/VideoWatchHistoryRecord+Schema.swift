@preconcurrency import GRDB

extension VideoWatchHistoryRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let sourceID: Column = Column("sourceID")
        static let vodID: Column = Column("vodID")
        static let workKey: Column = Column("workKey")
        static let videoTitle: Column = Column("videoTitle")
        static let episodeTitle: Column = Column("episodeTitle")
        static let episodeKey: Column = Column("episodeKey")
        static let sourceIndex: Column = Column("sourceIndex")
        static let episodeIndex: Column = Column("episodeIndex")
        static let detailURL: Column = Column("detailURL")
        static let playPageURL: Column = Column("playPageURL")
        static let candidateMediaURL: Column = Column("candidateMediaURL")
        static let candidateMediaKind: Column = Column("candidateMediaKind")
        static let playbackStatusJSON: Column = Column("playbackStatusJSON")
        static let playbackRequestConfigJSON: Column = Column("playbackRequestConfigJSON")
        static let coverURL: Column = Column("coverURL")
        static let sourceName: Column = Column("sourceName")
        static let lastPlaybackTime: Column = Column("lastPlaybackTime")
        static let duration: Column = Column("duration")
        static let visitedAt: Column = Column("visitedAt")
        static let updatedAt: Column = Column("updatedAt")
        static let previousEpisodeURL: Column = Column("previousEpisodeURL")
        static let nextEpisodeURL: Column = Column("nextEpisodeURL")
        static let sourceSnapshotJSON: Column = Column("sourceSnapshotJSON")
    }
}
