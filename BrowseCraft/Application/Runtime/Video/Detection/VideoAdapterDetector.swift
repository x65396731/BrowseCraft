import Foundation
import BrowseCraftCore

struct VideoAdapterDetectionInput: Hashable {
    var url: URL
    var html: String?
    var headers: [String: String]

    init(url: URL, html: String? = nil, headers: [String: String] = [:]) {
        self.url = url
        self.html = html
        self.headers = headers
    }
}

struct VideoAdapterDetection: Hashable {
    var adapter: VideoAdapter
    var confidence: Double
    var reasons: [String]
    var warnings: [String]
}

protocol VideoAdapterDetecting {
    func detect(_ input: VideoAdapterDetectionInput) -> VideoAdapterDetection
}

// 中文注释：兼容旧调用点；实际检测逻辑由 VideoSourceDetector 产出适配器、渲染和播放三层结果。
struct VideoAdapterDetector: VideoAdapterDetecting {
    private let sourceDetector: any VideoSourceDetecting

    init(sourceDetector: any VideoSourceDetecting = VideoSourceDetector()) {
        self.sourceDetector = sourceDetector
    }

    func detect(_ input: VideoAdapterDetectionInput) -> VideoAdapterDetection {
        let detection: VideoSourceDetection = self.sourceDetector.detect(
            VideoSourceDetectionInput(
                url: input.url,
                html: input.html,
                headers: input.headers
            )
        )

        return VideoAdapterDetection(
            adapter: detection.adapter,
            confidence: detection.confidence,
            reasons: self.compatibilityReasons(from: detection),
            warnings: detection.warnings
        )
    }

    private func compatibilityReasons(from detection: VideoSourceDetection) -> [String] {
        return detection.reasons + [
            "Render mode: \(detection.renderMode.rawValue).",
            "Playback mode: \(detection.playbackMode.rawValue)."
        ]
    }
}
