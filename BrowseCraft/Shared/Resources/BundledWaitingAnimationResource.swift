import Foundation

// 中文注释：只读的 App bundle 资源查找，与 BundledStartupAnimationResource 同理归在 Shared。
// 中文注释：品牌等待标记的循环视频（docs/design/Brand-Waiting-Mark-Design.md），兼容 Xcode 扁平复制和保留 Waiting 子目录两种打包方式。

struct BundledWaitingAnimationResource {
    enum ResourceError: LocalizedError {
        case missingVideo(fileName: String)

        var errorDescription: String? {
            switch self {
            case .missingVideo(let fileName):
                return "The bundled waiting animation resource \(fileName) could not be found."
            }
        }
    }

    /// 海报帧在资产目录里的名字：视频就绪前与开了「减弱动态效果」时显示。
    static let posterImageName: String = "BrandWaitingPoster"

    private static let resourceName: String = "brand-waiting"
    private static let resourceExtension: String = "mp4"

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func videoURL() throws -> URL {
        if let url: URL = self.bundle.url(
            forResource: Self.resourceName,
            withExtension: Self.resourceExtension
        ) {
            return url
        }

        if let url: URL = self.bundle.url(
            forResource: Self.resourceName,
            withExtension: Self.resourceExtension,
            subdirectory: "Waiting"
        ) {
            return url
        }

        throw ResourceError.missingVideo(
            fileName: "\(Self.resourceName).\(Self.resourceExtension)"
        )
    }
}
