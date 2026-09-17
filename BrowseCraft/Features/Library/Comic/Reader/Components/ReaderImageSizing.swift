import UIKit

// 中文注释：阅读器的解码目标宽度策略：按屏幕像素宽度解码。解码本身是共享 pipeline 的通用降采样机制
// （Shared/UI/DownsampledImageDecoder.swift），阅读器只负责在请求上声明宽度。
enum ReaderImageSizing {
    @MainActor
    static var targetPixelWidth: CGFloat {
        let screen: UIScreen = UIScreen.main
        return max(1, screen.bounds.width * screen.scale)
    }
}
