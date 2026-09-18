import UIKit
import XCTest
@testable import BrowseCraft

// 中文注释：随包位图资产的运行期闸门，与构建前脚本 `scripts/check-bundled-image-assets.sh`
// 共用同一份声明 `scripts/bundled-image-asset-budgets.txt`，避免两处各写一份而互相漂移。
// 脚本看的是仓库里的源文件（字节、形态、像素尺寸），这里看的是**编译进 App 之后还能不能解出画面**——
// 2026-09-18 把四张占位图从多档 PNG 换成单档 HEIC 时，这一层是必须的：
// 如果资产目录接受了 HEIC 但运行期解不出来，表现是占位图一片空白，不会崩溃也不会报错。
final class BundledImageAssetTests: XCTestCase {
    func testEveryDeclaredImageAssetDecodesAtItsDeclaredPixelSize() throws {
        let declarations: [Declaration] = try Self.declarations()
        XCTAssertFalse(declarations.isEmpty, "声明文件解析不出任何条目")

        for declaration in declarations where declaration.name != "AppIcon" {
            let image: UIImage? = UIImage(named: declaration.name)
            let unwrapped: UIImage = try XCTUnwrap(image, "资产 \(declaration.name) 加载不出来")

            // 中文注释：`size` 是点，乘 `scale` 才是像素。单档资产的 scale 为 1，像素即声明值。
            let pixelWidth: Int = Int((unwrapped.size.width * unwrapped.scale).rounded())
            let pixelHeight: Int = Int((unwrapped.size.height * unwrapped.scale).rounded())
            XCTAssertEqual(
                "\(pixelWidth)x\(pixelHeight)",
                declaration.pixelSize,
                "资产 \(declaration.name) 解出的像素尺寸与声明不一致"
            )

            // 中文注释：只判 UIImage 非 nil 不够——要真拿到 CGImage 才能说明解码器给出了画面。
            let cgImage: CGImage = try XCTUnwrap(unwrapped.cgImage, "资产 \(declaration.name) 拿不到 CGImage")
            XCTAssertGreaterThan(cgImage.width, 0, "资产 \(declaration.name) 解出的宽度为 0")
            XCTAssertGreaterThan(cgImage.height, 0, "资产 \(declaration.name) 解出的高度为 0")
        }
    }

    // MARK: - 声明文件

    private struct Declaration {
        let name: String
        let pixelSize: String
    }

    private static func declarations() throws -> [Declaration] {
        let contents: String = try String(contentsOf: Self.declarationURL(), encoding: .utf8)
        return contents.split(separator: "\n").compactMap { line in
            let trimmed: Substring = line.trimmingPrefix(while: { $0 == " " })
            guard trimmed.isEmpty == false, trimmed.hasPrefix("#") == false else {
                return nil
            }
            let columns: [Substring] = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 3 else {
                return nil
            }
            return Declaration(name: String(columns[0]), pixelSize: String(columns[2]))
        }
    }

    /// 中文注释：用 `#filePath` 回溯到仓库根，测试在模拟器里跑但读的是宿主机上的源文件。
    private static func declarationURL() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Resources
            .deletingLastPathComponent()  // Shared
            .deletingLastPathComponent()  // BrowseCraftTests
            .deletingLastPathComponent()  // 仓库根
            .appendingPathComponent("scripts/bundled-image-asset-budgets.txt")
    }
}
