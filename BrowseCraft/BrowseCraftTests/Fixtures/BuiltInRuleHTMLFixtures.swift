// 中文注释：BuiltInRuleHTMLFixtures 集中保存解析器回归测试用 HTML。
// 中文注释：解析测试只关心断言逻辑，页面样例统一放这里，减少 review 时被大段 HTML 干扰。
enum BuiltInRuleHTMLFixtures {
    /// 中文注释：内置列表页样例，覆盖标题、详情链接、封面和最新话标签。
    static let listHTML: String = """
    <main>
      <a href="https://example.test/cn/comics/55355">
        <img src="https://image.example/comics/55355-9e7018.jpg" alt="猎人游戏W">
        <div>第07话</div>
      </a>
      <a href="https://example.test/cn/comics/55354">
        <img data-src="https://image.example/comics/55354-3483fc.jpg" alt="1步前进 2步后退">
        <div>短篇 [完]</div>
      </a>
    </main>
    """

    /// 中文注释：内置详情页样例，包含正文章节容器和干扰用排行链接。
    static let detailHTML: String = """
    <main>
      <div data-flux-heading>猎人游戏W</div>
      <aside>
        <a href="https://example.test/cn/chapters/999001">排行第262话</a>
        <a href="https://example.test/cn/chapters/999002">排行第06话</a>
      </aside>
      <div x-data="{ chapters: [{ id: 818145, title: '第02话' }, { id: 818144, title: '第01话' }] }">
        <div class="grid grid-cols-3 gap-4">
          <a href="https://example.test/cn/chapters/818145">第02话</a>
          <a href="https://example.test/cn/chapters/818144">第01话</a>
        </div>
      </div>
    </main>
    """

    /// 中文注释：缺少章节容器的详情页样例，用来确认解析器不会退回全页面宽泛匹配。
    static let detailHTMLWithoutChapterContainer: String = """
    <main>
      <div data-flux-heading>猎人游戏W</div>
      <aside>
        <a href="https://example.test/cn/chapters/999001">排行第262话</a>
        <a href="https://example.test/cn/chapters/999002">排行第06话</a>
      </aside>
    </main>
    """

    /// 中文注释：内置阅读页样例，覆盖面包屑、上下章导航、src/data-src 图片。
    static let readerHTML: String = """
    <main>
      <nav>
        <a href="https://example.test/cn/comics/123">随机漫画</a>
      </nav>
      <div data-flux-breadcrumbs-item>
        <a href="https://example.test/cn/comics/20515">哥布林殺手</a>
      </div>
      <div data-flux-breadcrumbs-item>
        <div class="truncate whitespace-nowrap">第83話</div>
      </div>
      <section>
        <img class="page w-full mx-auto" src="https://image.example/chapters/735147/1-95aef5.jpg" alt="哥布林殺手 - 第83話: 第1页">
        <img class="lozad page w-full mx-auto" data-src="https://image.example/chapters/735147/2-77d7bd.jpg" alt="哥布林殺手 - 第83話: 第2页">
        <img class="lozad page w-full mx-auto" data-src="https://image.example/chapters/735147/3-6d79f1.jpg" src="https://placeholder.example/blank.gif" alt="哥布林殺手 - 第83話: 第3页">
      </section>
      <footer>
        <a href="https://example.test/cn/chapters/727041">上一话</a>
        <a href="https://example.test/cn/comics/20515">返回目录</a>
        <a href="https://example.test/cn/chapters/735148">下一话</a>
      </footer>
    </main>
    """
}
