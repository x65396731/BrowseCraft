import ImageIO
import Nuke
import UIKit

// 中文注释：「按目标宽度降采样解码」是通用机制：任何 kind 只要在 ImageRequest 上声明目标像素宽度，
// 共享 pipeline 就用 CGImageSource 缩略图接口按该宽度解码，不再先解出全尺寸位图再缩小。
// 长条漫画一页可达几十 MB 位图，先全尺寸解码再缩小会让内存与 CPU 瞬时翻倍；这是阅读器接入它的原因。
// 未声明目标宽度的请求走 Nuke 默认解码器，行为不变。

extension ImageRequest.UserInfoKey {
    /// 中文注释：请求级声明——解码输出的目标像素宽度（CGFloat）。
    static let downsampleTargetPixelWidth: ImageRequest.UserInfoKey = "com.browsecraft.image.downsampleTargetPixelWidth"
}

extension ImageRequest {
    /// 中文注释：解码输出的目标像素宽度；nil 表示不降采样。
    /// 注意：解码后的内存缓存键不含该宽度——同一地址在同一进程内按首次声明的宽度缓存，
    /// 当前只有阅读器使用且宽度为屏幕宽度，横竖屏切换时复用另一宽度的位图只影响缩放质量，不影响正确性。
    var downsampleTargetPixelWidth: CGFloat? {
        get {
            return self.userInfo[.downsampleTargetPixelWidth] as? CGFloat
        }
        set {
            self.userInfo[.downsampleTargetPixelWidth] = newValue
        }
    }
}

/// 中文注释：Nuke 解码器工厂——由 ImageCacheConfigurator 装进共享 pipeline 的 `makeImageDecoder`。
enum DownsamplingImageDecoding {
    @Sendable static func makeDecoder(for context: ImageDecodingContext) -> (any ImageDecoding)? {
        guard let targetPixelWidth: CGFloat = context.request.downsampleTargetPixelWidth else {
            return ImageDecoderRegistry.shared.decoder(for: context)
        }
        return DownsamplingImageDecoder(targetPixelWidth: targetPixelWidth)
    }
}

/// 中文注释：只在数据完整后解码（不做渐进预览）；动图交还 Nuke 默认解码器以保留帧数据。
struct DownsamplingImageDecoder: ImageDecoding {
    let targetPixelWidth: CGFloat

    func decode(_ data: Data) throws -> ImageContainer {
        if DownsampledImageDecoder.isAnimated(data: data) {
            return try ImageDecoders.Default().decode(data)
        }
        guard let image: UIImage = DownsampledImageDecoder.decode(data: data, targetPixelWidth: self.targetPixelWidth) else {
            throw ImageDecodingError.unknown
        }
        return ImageContainer(image: image)
    }
}

/// 中文注释：与 Nuke 无关的解码函数；受保护资源解密后的内存数据也走这里，与 pipeline 路径同一套输出规格。
enum DownsampledImageDecoder {
    /// 中文注释：任何一边都不超过这个像素数，避免超长条图触发 UIKit 纹理上限。
    static let maximumPixelDimension: CGFloat = 16_384

    static func isAnimated(data: Data) -> Bool {
        guard let source: CGImageSource = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return false
        }
        return CGImageSourceGetCount(source) > 1
    }

    static func decode(data: Data, targetPixelWidth: CGFloat) -> UIImage? {
        guard let source: CGImageSource = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return UIImage(data: data).flatMap { image in
                DownsampledImageRenderer.normalizedImage(
                    image,
                    targetPixelWidth: targetPixelWidth
                )
            }
        }

        if CGImageSourceGetCount(source) > 1 {
            return UIImage(data: data)
        }

        let sourceSize: CGSize? = Self.orientedPixelSize(source: source)
        let maximumPixelSize: CGFloat = sourceSize.map { size in
            DownsampledImageRenderer.outputSize(
                sourcePixelSize: size,
                targetPixelWidth: targetPixelWidth
            )
            .maximumDimension
        } ?? Self.maximumPixelDimension
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]

        guard let cgImage: CGImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return DownsampledImageRenderer.normalizedImage(
            UIImage(cgImage: cgImage),
            targetPixelWidth: targetPixelWidth
        )
    }

    private static func orientedPixelSize(source: CGImageSource) -> CGSize? {
        guard let properties: [CFString: Any] = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any],
        let widthNumber: NSNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
        let heightNumber: NSNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        let width: CGFloat = CGFloat(widthNumber.doubleValue)
        let height: CGFloat = CGFloat(heightNumber.doubleValue)
        guard width > 0,
              height > 0 else {
            return nil
        }

        let orientation: UInt32 = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        if [5, 6, 7, 8].contains(orientation) {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }
}

/// 中文注释：统一转成标准色彩空间并按目标宽度定尺，避免保留超大原图和不兼容 PNG 色彩空间。
private enum DownsampledImageRenderer {
    static func normalizedImage(_ image: UIImage, targetPixelWidth: CGFloat) -> UIImage? {
        guard image.images == nil,
              image.size.width > 0,
              image.size.height > 0 else {
            return image
        }

        let sourcePixelSize: CGSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let outputSize: CGSize = self.outputSize(
            sourcePixelSize: sourcePixelSize,
            targetPixelWidth: targetPixelWidth
        )
        let format: UIGraphicsImageRendererFormat = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = image.cgImage.map(self.isOpaque) ?? false
        format.preferredRange = .standard

        let renderer: UIGraphicsImageRenderer = UIGraphicsImageRenderer(
            size: outputSize,
            format: format
        )
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }

    static func outputSize(sourcePixelSize: CGSize, targetPixelWidth: CGFloat) -> CGSize {
        guard sourcePixelSize.width > 0,
              sourcePixelSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }

        let widthScale: CGFloat = max(1, targetPixelWidth) / sourcePixelSize.width
        let dimensionScale: CGFloat = DownsampledImageDecoder.maximumPixelDimension /
            max(sourcePixelSize.width, sourcePixelSize.height)
        let scale: CGFloat = min(1, widthScale, dimensionScale)
        return CGSize(
            width: max(1, floor(sourcePixelSize.width * scale)),
            height: max(1, floor(sourcePixelSize.height * scale))
        )
    }

    private static func isOpaque(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return true
        case .alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast:
            return false
        @unknown default:
            return false
        }
    }
}

private extension CGSize {
    var maximumDimension: CGFloat {
        return max(self.width, self.height)
    }
}
