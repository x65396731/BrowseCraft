import Foundation

// 中文注释：只读的 App bundle 资源查找，没有网络、数据库或 keychain 这类副作用，因此归在 Shared 而非
// Infrastructure：界面层可以直接使用，不必再经 Application 端口注入（2026-09-18 收敛边界豁免时归位）。
// 中文注释：集中解析启动动画资源，兼容 Xcode 扁平复制和保留 Startup 子目录两种打包方式。

struct BundledStartupAnimationResource {
    enum ResourceError: LocalizedError {
        case missingVideo(fileName: String)

        var errorDescription: String? {
            switch self {
            case .missingVideo(let fileName):
                return "The bundled startup animation resource \(fileName) could not be found."
            }
        }
    }

    private static let resourceName: String = "startup-animation"
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
            subdirectory: "Startup"
        ) {
            return url
        }

        throw ResourceError.missingVideo(
            fileName: "\(Self.resourceName).\(Self.resourceExtension)"
        )
    }
}
