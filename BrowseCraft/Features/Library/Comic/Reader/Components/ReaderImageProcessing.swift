import ImageIO
import Nuke
import UIKit

// 中文注释：Reader 图片统一在后台按显示宽度缩放并转为标准色彩空间，避免保留超大原图和不兼容 PNG 色彩空间。
enum ReaderImageSizing {
    static let maximumPixelDimension: CGFloat = 16_384

    @MainActor
    static var targetPixelWidth: CGFloat {
        let screen: UIScreen = UIScreen.main
        return max(1, screen.bounds.width * screen.scale)
    }
}

struct ReaderImageProcessor: ImageProcessing, Hashable {
    let targetPixelWidth: CGFloat

    func process(_ image: UIImage) -> UIImage? {
        return ReaderImageRenderer.normalizedImage(
            image,
            targetPixelWidth: self.targetPixelWidth
        )
    }

    var identifier: String {
        return "com.browsecraft.reader.image?" +
            "width=\(Int(self.targetPixelWidth.rounded()))&" +
            "max=\(Int(ReaderImageSizing.maximumPixelDimension))"
    }

    var hashableIdentifier: AnyHashable {
        return self
    }
}

enum ReaderImageDecoder {
    static func decode(data: Data, targetPixelWidth: CGFloat) -> UIImage? {
        guard let source: CGImageSource = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return UIImage(data: data).flatMap { image in
                ReaderImageRenderer.normalizedImage(
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
            ReaderImageRenderer.outputSize(
                sourcePixelSize: size,
                targetPixelWidth: targetPixelWidth
            )
            .maximumDimension
        } ?? ReaderImageSizing.maximumPixelDimension
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

        return ReaderImageRenderer.normalizedImage(
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

private enum ReaderImageRenderer {
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
        let dimensionScale: CGFloat = ReaderImageSizing.maximumPixelDimension /
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
