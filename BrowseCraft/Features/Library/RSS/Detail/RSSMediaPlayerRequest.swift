import Foundation

struct RSSMediaPlayerRequest: Identifiable {
    let id: String
    let media: RSSContentPayload.Media
    let title: String

    init(media: RSSContentPayload.Media, title: String) {
        self.id = "\(media.kind.rawValue)-\(media.playbackMode.rawValue)-\(media.url)"
        self.media = media
        self.title = title
    }
}
