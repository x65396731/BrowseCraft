import Foundation

struct DiscoveredRSSFeedItem: Identifiable, Hashable {
    let id: String
    let feedURL: URL
    let siteURL: URL
    let title: String
    let itemCount: Int
    let firstItemTitle: String?

    init(
        feedURL: URL,
        siteURL: URL,
        title: String,
        itemCount: Int,
        firstItemTitle: String?
    ) {
        self.id = feedURL.absoluteString
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.title = title
        self.itemCount = itemCount
        self.firstItemTitle = firstItemTitle
    }
}
