import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：BC-BOOK-050 模拟器逮到：sfacg 作品页 302 到 http:// 的移动站再 301 回 https，ATS 在 http 那一跳拒掉。
// 跳转目标里的 http 在客户端升成 https（与有声书 mp3 同一纪律），本来就是 https 的原样不动。
struct AlamofireHTTPClientRedirectTests {
    @Test func httpRedirectTargetsAreUpgradedToHTTPS() {
        #expect(AlamofireHTTPClient.httpsUpgraded(URL(string: "http://m.sfacg.com/b/540307/")!)?.absoluteString == "https://m.sfacg.com/b/540307/")
        #expect(AlamofireHTTPClient.httpsUpgraded(URL(string: "http://m.sfacg.com:80/b/540307/?a=1#top")!)?.absoluteString == "https://m.sfacg.com/b/540307/?a=1#top")
        #expect(AlamofireHTTPClient.httpsUpgraded(URL(string: "https://m.sfacg.com/b/540307/")!) == nil, "已是 https 不动")
        #expect(AlamofireHTTPClient.httpsUpgraded(URL(string: "file:///tmp/x")!) == nil)
    }
}
