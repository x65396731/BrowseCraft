import Foundation
import BrowseCraftCore

struct VideoSourceDetectionInput: Hashable {
    var url: URL
    var html: String?
    var headers: [String: String]

    init(url: URL, html: String? = nil, headers: [String: String] = [:]) {
        self.url = url
        self.html = html
        self.headers = headers
    }
}

struct VideoSourceDetection: Hashable {
    var adapter: VideoAdapter
    var renderMode: VideoRenderMode
    var playbackMode: VideoPlaybackMode
    var confidence: Double
    var reasons: [String]
    var warnings: [String]
}

enum VideoRenderMode: String, Codable, Hashable {
    case staticHTML
    case webViewRequired
}

enum VideoPlaybackMode: String, Codable, Hashable {
    case directMedia
    case iframe
    case unresolved
}

protocol VideoSourceDetecting {
    func detect(_ input: VideoSourceDetectionInput) -> VideoSourceDetection
}
