import Foundation

// 中文注释：RSSMediaClassifier 在 RSS 映射边界内收敛标准媒体字段与少量已知播放页链接分类。
struct RSSMediaClassifier {
    func resolvedMedia(
        feedMedia: RSSContentPayload.Media?,
        link: URL?,
        coverURL: URL?
    ) -> RSSContentPayload.Media? {
        if var media: RSSContentPayload.Media = feedMedia {
            if media.posterURL == nil {
                media.posterURL = coverURL?.absoluteString
            }
            if media.sourcePageURL == nil,
               media.playbackMode == .directMedia {
                media.sourcePageURL = link?.absoluteString
            }
            return media
        }

        guard let link: URL = link else {
            return nil
        }

        if let directKind: RSSContentPayload.MediaKind = Self.directMediaKind(for: link) {
            return RSSContentPayload.Media(
                kind: directKind,
                playbackMode: .directMedia,
                url: link.absoluteString,
                mimeType: Self.mimeType(for: link),
                duration: nil,
                posterURL: coverURL?.absoluteString,
                sourcePageURL: nil
            )
        }

        if let pageKind: RSSContentPayload.MediaKind = Self.knownPlaybackPageKind(for: link) {
            return RSSContentPayload.Media(
                kind: pageKind,
                playbackMode: .webPage,
                url: link.absoluteString,
                mimeType: nil,
                duration: nil,
                posterURL: coverURL?.absoluteString,
                sourcePageURL: link.absoluteString
            )
        }

        return nil
    }

    static func directMediaKind(mimeType: String?, url: URL?) -> RSSContentPayload.MediaKind? {
        let normalizedMimeType: String = mimeType?.lowercased() ?? ""
        if normalizedMimeType.hasPrefix("audio/") {
            return .audio
        }
        if normalizedMimeType.hasPrefix("video/") || normalizedMimeType == "application/vnd.apple.mpegurl" || normalizedMimeType == "application/x-mpegurl" {
            return .video
        }

        guard let url: URL = url else {
            return nil
        }

        return Self.directMediaKind(for: url)
    }

    static func directMediaKind(for url: URL) -> RSSContentPayload.MediaKind? {
        let pathExtension: String = url.pathExtension.lowercased()
        if Self.audioExtensions.contains(pathExtension) {
            return .audio
        }
        if Self.videoExtensions.contains(pathExtension) {
            return .video
        }

        return nil
    }

    static func imageKind(mimeType: String?, url: URL?) -> Bool {
        let normalizedMimeType: String = mimeType?.lowercased() ?? ""
        if normalizedMimeType.hasPrefix("image/") {
            return true
        }

        guard let url: URL = url else {
            return false
        }

        return Self.imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "ogg", "oga":
            return "audio/ogg"
        case "wav":
            return "audio/wav"
        case "flac":
            return "audio/flac"
        case "mp4", "m4v":
            return "video/mp4"
        case "webm":
            return "video/webm"
        case "mov":
            return "video/quicktime"
        case "m3u8":
            return "application/vnd.apple.mpegurl"
        default:
            return nil
        }
    }

    private static func knownPlaybackPageKind(for url: URL) -> RSSContentPayload.MediaKind? {
        if let pattern: KnownPlaybackPagePattern = Self.knownPlaybackPagePatterns.first(where: { pattern in
            pattern.matches(url)
        }) {
            return pattern.kind
        }

        return nil
    }

    private static let knownPlaybackPagePatterns: [KnownPlaybackPagePattern] = [
        KnownPlaybackPagePattern(
            hosts: ["gcores.com", "www.gcores.com"],
            pathPrefixes: ["/radios/"],
            kind: .audio
        ),
        KnownPlaybackPagePattern(
            hosts: ["gcores.com", "www.gcores.com"],
            pathPrefixes: ["/videos/"],
            kind: .video
        ),
        KnownPlaybackPagePattern(
            hostSuffixes: ["youtube.com"],
            pathPrefixes: ["/watch", "/shorts/", "/embed/"],
            kind: .video
        ),
        KnownPlaybackPagePattern(
            hosts: ["youtu.be"],
            pathPrefixes: ["/"],
            kind: .video
        ),
        KnownPlaybackPagePattern(
            hostSuffixes: ["vimeo.com"],
            pathPrefixes: ["/"],
            kind: .video
        )
    ]

    private static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "ogg", "oga", "wav", "flac"]
    private static let videoExtensions: Set<String> = ["mp4", "m4v", "webm", "mov", "m3u8"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif"]
}

private struct KnownPlaybackPagePattern {
    var hosts: Set<String> = []
    var hostSuffixes: Set<String> = []
    var pathPrefixes: [String]
    var kind: RSSContentPayload.MediaKind

    func matches(_ url: URL) -> Bool {
        let host: String = url.host?.lowercased() ?? ""
        let path: String = url.path.lowercased()

        guard self.matchesHost(host) else {
            return false
        }

        return self.pathPrefixes.contains { pathPrefix in
            path.hasPrefix(pathPrefix)
        }
    }

    private func matchesHost(_ host: String) -> Bool {
        if self.hosts.contains(host) {
            return true
        }

        return self.hostSuffixes.contains { suffix in
            host == suffix || host.hasSuffix(".\(suffix)")
        }
    }
}
