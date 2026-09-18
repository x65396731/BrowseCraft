import BrowseCraftCore
import CoreGraphics
import Testing
@testable import BrowseCraft

// 中文注释：封面与缩略图的请求标识——**尺寸没测到就不构造**。
//
// 这条是 2026-09-18 真机日志逼出来的：`displaySize` 由 `onGeometryChange` 回填、初值是 zero，
// 所以 `.task(id:)` 会先带着零尺寸触发一次、测量后再触发一次，同一张封面的 `stage=image`
// 请求在真机日志里出现 2 到 3 行。零尺寸那次不声明缩略选项，等于按原图解码，
// 正好抵消掉按单元格尺寸降采样的第一屏收益。
struct RemoteImageRequestIdentityTests {
    @Test func unmeasuredSizeProducesNoIdentity() {
        #expect(Self.identity(displaySize: .zero) == nil)
    }

    @Test func partiallyMeasuredSizeProducesNoIdentity() {
        #expect(Self.identity(displaySize: CGSize(width: 129, height: 0)) == nil)
        #expect(Self.identity(displaySize: CGSize(width: 0, height: 194)) == nil)
    }

    @Test func measuredSizeProducesAnIdentity() throws {
        let identity: RemoteImageRequestIdentity = try #require(
            Self.identity(displaySize: CGSize(width: 129, height: 194))
        )
        #expect(identity.displaySize == CGSize(width: 129, height: 194))
    }

    /// 中文注释：尺寸进标识，是为了让同一地址在不同尺寸的位置各自解码、互不串用。
    @Test func sizeParticipatesInIdentity() throws {
        let small: RemoteImageRequestIdentity = try #require(Self.identity(displaySize: CGSize(width: 64, height: 88)))
        let large: RemoteImageRequestIdentity = try #require(Self.identity(displaySize: CGSize(width: 129, height: 194)))
        #expect(small != large)
    }

    private static func identity(displaySize: CGSize) -> RemoteImageRequestIdentity? {
        return RemoteImageRequestIdentity(
            urlString: "https://example.test/cover.jpg",
            refererURLString: nil,
            requestConfig: nil,
            additionalHeaders: nil,
            displaySize: displaySize
        )
    }
}
