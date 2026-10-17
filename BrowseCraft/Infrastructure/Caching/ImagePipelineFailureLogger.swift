import BrowseCraftLog
import Foundation
@preconcurrency import Nuke

// 中文注释：图片的公共钩子（Logging-Design.md `BCA-OBS-014`）：共享管线与缩略图管线的加载失败都在这里记一条 error，
// 封面、缩略图与漫画页因此不用各自打点。成功只在 debug 级记，避免逐张图刷满本机日志。

final class ImagePipelineFailureLogger: ImagePipelineDelegate {
    static let shared: ImagePipelineFailureLogger = ImagePipelineFailureLogger()

    private init() {}

    func imageTask(
        _ task: ImageTask,
        didCompleteWithResult result: Result<ImageResponse, ImagePipeline.Error>,
        pipeline: ImagePipeline
    ) {
        Self.log(task: task, result: result, pipeline: "shared")
    }

    static func log(task: ImageTask, result: Result<ImageResponse, ImagePipeline.Error>, pipeline: String) {
        let url: URL? = task.request.url
        switch result {
        case .success:
            AppLog.debug(.image, "image-loaded", ["pipeline": .code(pipeline), "host": .host(url)])
        case .failure(let error):
            if case .dataMissingInCache = error {
                return
            }
            if case .dataLoadingFailed(let underlying) = error, (underlying as? URLError)?.code == .cancelled {
                return
            }
            AppLog.error(.image, "image-load-failed", [
                "pipeline": .code(pipeline),
                "host": .host(url),
                "path": .path(url),
                "error": .error(error)
            ])
        }
    }
}
