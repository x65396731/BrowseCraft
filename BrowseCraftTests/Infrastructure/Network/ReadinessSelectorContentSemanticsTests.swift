import BrowseCraftCore
import BrowseCraftDomain
import XCTest
@testable import BrowseCraft

// 中文注释：就绪选择器的**语义闸门**——它钉住「`ready` 该取什么值」这条判据，不依赖任何站点。
//
// 问题：当 `ready` 比要提取的内容更宽（页面上先有同类元素，内容稍后才追加进来），
// 「命中数稳定」会在内容到达之前就满足，于是提前返回、丢掉内容。
//
// 2026-09-18 实测（本文件的固定输入，内容在 1,300ms 注入）：
//   宽选择器 `ul`          1,112ms   0 条   ← 丢内容
//   内容选择器 `.chapters li` 2,092ms  20 条
//   不声明（历史机制）      2,960ms  20 条
//
// 结论：**`ready` 必须命中要提取的内容本身，不能是内容到达前就存在的容器。**
// 取对了既不丢内容又比历史机制快约 0.9 秒。规则生成侧据此只交付内容选择器
// （fwq `BC-COMIC-131` 的 list 层、以及详情层的同类条款）。
//
// 另一条边界，同日一并量到：内容若晚于历史机制的 12 轮上限（本机约 2.4s）才到，
// **三种取法都丢**——那是既有上限，不是 `ready` 引入的问题。
final class ReadinessSelectorContentSemanticsTests: XCTestCase {
    /// 中文注释：页面先有 3 个导航用的 `<ul>`，1,300ms 后才追加装 20 条章节的第 4 个 `<ul>`。
    /// 注入时刻选在加载器地板（约 1.1s）之后、历史机制上限（约 2.4s）之前，三种取法才分得开。
    private static let fixture: String = """
    <html><body>
      <ul id="nav1"><li>a</li></ul>
      <ul id="nav2"><li>b</li></ul>
      <ul id="nav3"><li>c</li></ul>
      <div id="host"></div>
      <script>
        setTimeout(function () {
          var host = document.getElementById('host');
          var list = document.createElement('ul');
          list.className = 'chapters';
          for (var i = 0; i < 20; i++) {
            var row = document.createElement('li');
            row.className = 'chapter';
            row.textContent = 'Chapter ' + i;
            list.appendChild(row);
          }
          host.appendChild(list);
        }, 1300);
      </script>
    </body></html>
    """

    func testWeakSelectorReturnsBeforeTheContentArrives() async throws {
        let (elapsed, chapters): (Int, Int) = try await Self.load(readinessSelector: "ul")
        print("[weak-risk] 宽选择器 ul: 耗时=\(elapsed)ms 章节数=\(chapters)")
        XCTAssertEqual(chapters, 0, "宽选择器在内容到达前就满足了数量稳定——这正是要钉住的风险")
        XCTAssertLessThan(elapsed, 1300, "提前返回发生在内容注入之前")
    }

    func testItemSelectorWaitsForTheContent() async throws {
        let (elapsed, chapters): (Int, Int) = try await Self.load(readinessSelector: ".chapters li")
        print("[weak-risk] 内容选择器 .chapters li: 耗时=\(elapsed)ms 章节数=\(chapters)")
        XCTAssertEqual(chapters, 20, "以要提取的内容本身作判据时，必须等到内容齐了")
        XCTAssertGreaterThanOrEqual(elapsed, 1300)
    }

    func testBaselineAlsoWaits() async throws {
        let (elapsed, chapters): (Int, Int) = try await Self.load(readinessSelector: nil)
        print("[weak-risk] 不声明: 耗时=\(elapsed)ms 章节数=\(chapters)")
        XCTAssertEqual(chapters, 20, "历史机制会等到页面稳定，内容不丢")
    }

    @MainActor
    private static func load(readinessSelector: String?) async throws -> (Int, Int) {
        let loader: WKWebViewHTMLLoader = WKWebViewHTMLLoader(domStabilityPolicy: .baseline)
        let encoded: String = fixture.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let url: URL = try XCTUnwrap(URL(string: "data:text/html;charset=utf-8,\(encoded)"))
        let request: PageLoadRequest = PageLoadRequest(
            url: url,
            requestConfig: RequestConfig(needsWebView: true),
            sourceContext: nil,
            readinessSelector: readinessSelector
        )
        let started: Date = Date()
        let response: PageContentResponse = try await loader.loadRenderedContent(request)
        let elapsed: Int = Int(Date().timeIntervalSince(started) * 1000)
        let chapters: Int = response.content.components(separatedBy: "class=\"chapter\"").count - 1
        return (elapsed, chapters)
    }
}
