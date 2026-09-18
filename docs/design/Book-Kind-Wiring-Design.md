# 读书 kind（book）App 侧接线

影响范围：BrowseCraftAPIKit、BrowseCraftDomain、BrowseCraftCore、BrowseCraftRuntime、BrowseCraft 五个仓库；影视线与漫画线代码零改动。顺序与发布策略已由用户裁决（第四、五节）。本地文件导入线的入口已按用户裁决藏起（[本地书籍导入](Local-Book-Import-Design.md) 第八节），其阅读器 / 书签 / 三张表留给批次 B / C 复用。

> 实施与验证状态见 [STATUS.md](../STATUS.md)；立项与落地的叙事事实见 [status-log.md](../history/status-log.md)。

## 一、结论

1. `BCA-BOOK-001` Readium（`readium/swift-toolkit`）只服务读书 kind：EPUB/PDF/有声书 Navigator 与 `Locator` 书签模型。
   漫画线保持自研阅读器，不得接 Readium 的 CBZ 分支；影视线不受影响。Readium 内部使用 SwiftSoup 不算越界（`BCA-ARCH-001`）。
1. `BCA-RUNTIME-002` book 是 App 里的第四种 `SourceRuntimeKind`（comic / video / plugin 之后），按现有 comic 的分流模式扩展，不在通用执行器里加 kind 特判。
2. 规则合同以规则仓库 `docs/rules/book-catalog-profile.md`（`BC-BOOK-001` ~ `BC-BOOK-012`）为准：外层 `id / name / baseURL / kind="book" / ruleJSON`，内层**只有原生 V2**（`version=2`、`site`、`sharedRequest`、`pages[]`、`ruleSets{listRules, detailRules, readerRules, searchRules?}`），没有 V1 兼容层，Core 不得为它虚构 `list / detail / gallery` 顶层字段。
3. 终端层与漫画不同：reader 规则每条恰好一个 `variant`（`text-dom | text-api | audio-media`）与 `contentType`（`text | audio`）。App 把一部作品装成一份 RWPM（`BC-BOOK-012`）喂 Readium：文字走 EPUB Navigator（`readingOrder[].type = text/html`，正文由 App 按 reader 规则取容器内段落装成 XHTML），有声走 Audio Navigator（远程 mp3 href）。CBZ 分支不接。
4. `BCA-RUNTIME-004` **兼容硬约束**：目录列表接口在 APIKit 是整表解码且 `BrowseCraftCatalogSourceKind` 是封闭枚举（`Catalog/BrowseCraftCatalogAPI.swift`），App Domain 的 `CatalogSourceKind` 同样封闭——只要目录里出现一条 `kind: book`，**所有旧版 App 的整个目录列表都解码失败**。因此 book catalog 在 App 侧宽容解码版本上线之前**不得发布**到 `/catalog/sources`（第五节）。

## 二、已核对的现状

2026-09-13 立项前逐处只读核对的五仓现状表已整节归档，见 [history/Book-Kind-Wiring-batch-records.md](../history/Book-Kind-Wiring-batch-records.md)——
它记的是当时的代码形状，不是当前事实。

## 三、范围与分批（每批单独拍板、单独提交、单独推送）

**批次 A：合同与枚举（无 UI，可先于 build）**
- APIKit：`PortalRuleGenerationSourceKind.book`；`BrowseCraftCatalogSourceKind.book` + 目录列表未知 kind 逐条跳过（记录被跳过的 id 与 kind，不静默）；用例覆盖「列表里混入未知 kind 时其余条目仍可用」。
- Domain：`CatalogSourceKind.book`、`SourceConfiguration.book(BookSourceConfiguration)`（`rule: BookSiteRule`、`schemaVersion`、`packageMetadata`、`isEditable`，与 comic 同形）。
- Core：`SourceRuntimeKind.book`；`BookSiteRule` 模型（`site / sharedRequest / pages / ruleSets`，reader 规则为三变体的封闭枚举）与校验器（键集、枚举、`variant` ↔ `contentType` 配对、页引用可解析、`BC-BOOK-003` 字段归属）；两份真实 catalog 作解码固定输入。
- App：`RuleGenerationSourceKind.book`、`APIKitVideoGenerationTaskClient` 映射、`CatalogSourceMaterializer` 的 book 分支（把 catalog 装成 `SourceConfiguration.book`）；其余 `case .comic` 分流点按编译器报缺补齐，UI 文案先用最小占位。
- 验收：五仓各自测试全过；影视与漫画的既有用例零改动。

**批次 B：Runtime 与 RWPM 装配（首次整包 build 在此批之前）**
- Runtime：`Book/` 包——`BookSourceRuntimeFactory`（`guard case .book`）、list / detail / search loader 复用 comic 的 DOM 取值原语（`ExtractRule` 投影与 comic 同源）；`BookSourceReaderLoader` 按 `variant` 分派：`text-dom` 取容器 + `segmentation`（`elements` 取段落元素、`lineBreaks` 取 `<br>` 间文本节点），`text-api` 取 `textPath` 或 `itemPath`，`audio-media` 取 `media.item` 作用域内的 `media.url`（或 `mediaAPI`）；章内 `content.next` 拼成一份资源。
- Application：`BookPublicationAssembler`——detail → `metadata`，章节 → `readingOrder[]`（`title / order / href`），`text` 资源装成 XHTML、`audio` 资源按 `media.format` 映射 `type`；输出给 Readium `Publication`。**待核实**：文字资源如何喂 EPUB Navigator（本地 HTTP 服务 `ReadiumAdapterGCDWebServer` 已链接，或 data URL），在 build 通过后用 biquhua 章节做一次离线验证再定。
- 验收：两份真实 catalog 走 Runtime 出「段落 ≥ 12、17 条 mp3」的固定输入；build 后真机复核影视线与漫画线没被 Readium 波及（交接单第五节第 5 条）。

**批次 C：Features**
- `AddSourceView` 加 `bookSource` 入口（复用 `VideoGenerationInputView(sourceKind: .book)`）；Library 按 kind 显示书籍卡；阅读器：EPUB Navigator 与 Audio Navigator（Audio 无 UI，自建播放器界面）；书签用 `Locator` 序列化落库，与漫画、视频进度模型互不干扰；`Localizable.strings` 两种语言各加键（写完核对包内键数，`plutil -lint` 不可靠）。
- 验收：**用户真机**在 biquhua 读到正文、在 loyalbooks 听到音频才算交付；此前只能说「已接线、未验证」。

**不在范围**：本地文件导入（EPUB / PDF / M4B）、PDF Navigator、`text-api` 站（生成侧只有合成固定输入）、带签名音频、VIP 章正文为空的处理（`BC-BOOK-039` 无正例）。

## 四、顺序：先本地文件导入闭合阅读器

交接单第五节建议**先做本地文件导入把阅读器与书签闭合，再接站点抓取**。**用户裁决按交接单的顺序：先用本地 EPUB / M4B 把 Readium 阅读器与 `Locator` 书签跑通，站点抓取路后补。**因此实施顺序改为：① 首次整包 build（Readium 链接进来后从未 build 过）→ ② 本地文件导入（另出设计节：文件来源、`Publication` 打开、EPUB 与 Audio Navigator、书签落库）→ ③ 本文批次 A → B → C。批次 B 的装配器先接本地 `Publication`，站点路复用同一个 Navigator 与书签模型。

## 五、兼容与发布策略：不发布 + 服务器加 `kinds` 过滤

目录列表接口在旧版 App 里整表解码、kind 封闭，book 一旦发布即让旧版目录整体失效。三条路：

1. **不发布**：book catalog 只经生成任务的 `/outcomes` 与 200 cached 响应到达提交它的用户（那两条路 kind 是字符串，旧版不崩），目录接口不放 book，直到批次 A 的宽容解码版本上线并稳定。
2. **服务器过滤**：PortalCore 目录接口加 `kinds` 查询参数，缺省只返回 `video, comic`；新版 App 显式带 `kinds=video,comic,book`。改动在 PortalCore（无鉴权端点，属用户有意设计，参数不改变这一点）。
3. **两者都做**：先 1 后 2。

> **本节第 1 条已被取代。** 2026-09-14 用户裁决把 biquhua 的 book catalog 发布进公共目录，随后 loyalbooks 与 sfacg
> 同样发布（记录在第十六、十七节与 fwq `HANDOFF.md`）。当前策略是第 2 条单独生效：服务器 `kinds` 缺省不回 book，
> 新版 App 显式声明。状态见 [STATUS.md](../STATUS.md) 第 1 节。

**用户裁决第 3 条**：1 立即生效（book catalog 不发布进目录，已是现状）；2 由 PortalCore 立项实施——目录接口加 `kinds` 查询参数，缺省只返回 `video, comic`，新版 App 显式带 `kinds=video,comic,book`（设计与实施记录在 PortalCore `docs/architecture/rule-generation-migration-plan.md` §14）。

## 六、验证命令

```bash
cd ../BrowseCraftAPIKit && swift test
cd ../BrowseCraftDomain && swift test
cd ../BrowseCraftCore && swift test
cd ../BrowseCraftRuntime && swift test
scripts/regenerate-project.sh && xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft -destination 'generic/platform=iOS Simulator' build
```

Core 预期 218 条通过、4 条跳过（交接单第四节）；整包 build 已通过一次（2026-09-13，Debug / 模拟器），Readium 与 KSPlayer、Firebase 同目标链接没有符号或资源冲突；每批实施后重跑。

## 七、与其它文档的关系

- 规则合同：规则仓库 `docs/rules/book-catalog-profile.md`（App 消费的接口定稿）、`docs/rules/book-generation-design.md` `BC-BOOK-048`（本文即其 App 部分的立项）。
- 服务器接线：PortalCore `docs/architecture/rule-generation-migration-plan.md` §14。
- Readium 依赖与 SwiftSoup fork：本目录 `Readium-Integration-Handoff.md`。

## 八~十一、批次 A / B / C 落地记录与模拟器全流程走查

四节是过程记录，已整节归档，见 [history/Book-Kind-Wiring-batch-records.md](../history/Book-Kind-Wiring-batch-records.md)。
本文其余各节的编号保持原样，不重排——正文里有「第八节」「第十二节」这类互相引用。

## 十二、章节推入的栈序修正

- **成因**：`LibraryView` 用 `navigationDestination(item:)` 推详情（与漫画同款），详情里的章节却用 `NavigationLink(value:)` 走栈根的 `navigationDestination(for: LibraryBookRoute.self)`。栈上没有显式 path 绑定时，value 式推入进的是栈的内部 path，item 式推入是独立的呈现元素，两者混用后 SwiftUI 把 item 式的详情重新排到了最上面。
- **修法**：与 `ComicDetailView` 同款——`BookSiteDetailView` 自己持有 `selectedChapter` 并声明 `navigationDestination(item:)`，章节行改成 Button 设值；`LibraryBookRoute.siteChapter` 删除，`LibraryView` 把 `makeBookSiteReader` 作为闭包传给详情页。行字用 `Color.primary` 压回正文色（List 里的 Button 标签缺省染 tint）。
- `BCA-UI-002` **对第八节结论的补充**：「多级 `navigationDestination(for:)` 必须在栈根声明一次」仍成立；本节补的是另一条——**同一条推入链上不要混用 value 式与 item 式**，一条链选定一种。

## 十三、章内分页的停止判据

- **缺口**：`BookSourceRuntime.loadText` 按 `content.next` 逐页拼接，停止条件只有「指回已取过的页」与上限 50 页。biquhua 章内页与下一章共用同一个 `a#next`（文字一律「下一章」），末页的 `next` 指向下一章 `129024.html`——规则一给值，第 1 章会把后续章节一路吞到上限。
- **修法**：加第三条停止条件 `isInChapterPage(candidate, chapterURL:)`——候选地址必须是本章地址的**兄弟页**：同主机、同目录、同扩展名，末段 = 本章词干 + 非字母数字分隔符 + 页码（≥ 2）；本章地址自己已带页码时词干去掉「分隔符 + 页码」后算。与引擎 `_FUSED_PAGE_SEGMENT`（`BC-LIST-093`）同一形状。只看 URL 形状，不看链接文字。
- **不覆盖**：query 形的章内分页（`?page=2`）——首批语料没有样本，量到再加。
- **固定输入**：`BookSourceRuntimeEndToEndTests.biquhuaInChapterPagesAreJoinedAndStopAtNextChapter`（三页夹具 `biquhua-reader-110-129023{,-p2,-p3}.html` + 带 `next` 的 `biquhua-catalog-next.json`：拼接后段落多于单页、取页序列恰为三页、不取 `129024.html`）与 `inChapterPageGuardOnlyAcceptsSiblingPagesOfTheChapter`（十个形状用例）。

## 十四、book 列表分页在 ViewModel 被 kind 门挡住

- **成因**：`LibraryViewModel.selectedSourceSupportsListPagination` 写的是 `kind == .video || kind == .comic`——09-12 从只认影视放宽到漫画时的形状，book 后来接入没跟上。
- **修法**：加 `.book`。固定输入 `LibraryViewModelTests.bookListAdvancesToTheNextPageWhenRuntimeReportsOne`（与漫画同款：第 1 页报 nextPage=2 → 触底取第 2 页 → 报 nil 即停）；`TestSourceRuntimeResolver` 补 `bookRuntimeFactory`，`Harness.makeBookSource()` 用 biquhua-catalog 夹具物化。
- **待补的缺口**：规则目录里「已添加」的来源没有任何动作，服务器上更新了规则的用户拿不到新版本，只能删掉重加；应给已添加来源提供「更新规则」（同 id 再添加即覆盖本地规则，`AddCatalogSourceUseCase` 已支持）。

## 十五、页码标记清洗与阅读器标题

- **页码标记**：biquhua 每页正文首尾各一行「第(1/3)页」，规则 `content` 把它当段落。清洗放在 Runtime 拼页处（`joinedParagraphs(pages:)`），
  不放引擎：拼页时 App 知道「本章共 m 页、这段在第 k 页」，剔除条件是**整段只有「第 k/m 页」这一行且 k、m 与实际拼接页数对得上**，
  对不上（只取到一页、取页中途失败、正文原文提到「第 2/3 页」）原样保留。引擎侧要给规则 DSL 加剥除槽位、四处合同都要动，重得多。
- **阅读器标题**：此前用列表条目标题（带分类前缀「[玄幻]普罗之主」），详情页用 manifest 标题（详情规则清洗后「普罗之主」）。
  出版物加载后 `BookReaderViewModel.title` 改用 manifest 标题，加载前仍用列表标题占位。
- **固定输入**：`BookSourceRuntimeEndToEndTests.pageMarkersAreStrippedOnlyWhenTheyMatchTheJoinedPages`（七个形状 + 拼接）；
  三页拼接用例断言拼接后无标记、单页取法保留。

## 十六、站点有声作品的播放器

- **内核**：Readium `AudioNavigator`（AVPlayer + Locator）——播放 / 暂停 / seek / 上一章下一章 / 倍速 / AudioSession 全在 SDK 里；
  SDK **不带界面**，界面照抄 Readium TestApp 的 `AudiobookReader`（封面、进度条、快退 10 秒 / 上一章 / 播放暂停 / 下一章 / 快进 30 秒），
  落在 `AudiobookPlayerView`；锁屏 / 控制中心 / 耳机命令照抄其命令中心部分，落在 `AudiobookRemoteControls`（Now Playing 用 SDK 的 `NowPlayingInfo`）。
- **接线**：`BookReaderViewModel.openSite` 遇到有声 manifest 不再抛错——建 `AudioNavigator`，代理桥 `AudioNavigatorBridge` 把播放状态与位置回给 VM，
  位置走文字书同一条进度 / 书签链路；`BookReaderView` 在 `isAudiobook` 时切到播放页，出现即播、离开即停并落进度；详情页「Start / Continue Listening」、章节可点。
  `Info.plist` 的 `UIBackgroundModes` 加 `audio`。
- **两处只有接起来才逮到的缺口**：
  ① `AudioNavigator` 的媒体加载器只播 `publication.get(link)` 给得出资源的 href，远程 mp3 之前容器不认——`ReadiumSitePublicationBuilder` 用 `CompositeContainer` 把正文容器与 SDK 的 `HTTPContainer` 组合；
  ② 规则产出的 mp3 是 `http://www.archive.org/…`，App 没有全局 ATS 例外，URLSession 报 -1022——AVFoundation 只看 Readium 的自定义 scheme，真正发请求的是 `DefaultHTTPClient`，
  在其 `willStartRequest` 里 http → https（`SiteBookAudioHTTPClient`；代理是弱引用，由正文容器持有）。
- **顺带修的两处**：Runtime 列表第 1 页永远用页面自己的地址，不把 1 代进模板（loyalbooks `?page=1` 被站点 302 到 http）；
  详情页从阅读器 / 播放页退回时只重读续读位置、不重取详情（此前 manifest 已在就直接返回，「Continue Listening」出不来）。
- **固定输入**：`BookReaderViewModelTests.openingSiteAudiobookBuildsAnAudioNavigator`、`BookSourceRuntimeEndToEndTests`（音频 href 有资源、第 1 页用入口地址）、
  `SiteBookAudioHTTPClientTests`、`BookSiteDetailViewModelTests.returningToDetailRefreshesReadingProgressWithoutReloading`。
- **后面再改的**：界面样式；倍速与偏好入口（SDK 有 `AudioPreferences`，界面没露）；`mediaAPI` 与带签名音频仍无语料。

## 十七、`chapterListURL`：章节列表在从作品页单跳到达的目录页

- **背景**：sfacg 的作品页只带「点击阅读」（指向 `MainIndex/`）与最新一章，完整章节在目录页。规则合同 `detailRules[]` 只有 `chapterRule` / `chapterAPI`，
  表达不了这一跳。规则仓库设计书 6.1 节定了合同：`detailRules[].chapterListURL`（可选 `ExtractRule`，`url`），在作品页上取目录页地址。
- **合同语义（实施时定下，与立项文字不同处以本条为准）**：给了 `chapterListURL`，**`fields` 与 `chapterRule` 都在目录页上应用**——规则生成侧把目录页当作这次
  列表交接的详情文档（以作品页为 `requested_url` 取回，与重定向同一表达），标题等字段的选择器是在目录页上学到的（sfacg：`h1.story-title`）。
  作品页只用来取 `chapterListURL`。只与 `chapterRule` 搭配（Core 校验 `detail.chapterListURL`）。
- **App 侧改动（已落地）**：Core `BookDetailRule.chapterListURL: ExtractRule?`（Codable，缺省 nil，老 catalog 不受影响）；`BookSiteRuleValidator` 配对校验；
  `DefaultBookRuleParser.parseChapterListURL(document:rule:runtimeContext:) -> URL?`（规则没给即 nil；给了却取不到即 `missingRequiredValue`，不猜地址）；
  Runtime `loadDetail`：取作品页 → 有 `chapterListURL` 就取目录页（两次都算 `purpose: .detail`、referer 作品页）→ 在该页上 `parseDetail`。
- **固定输入**：Core `DefaultBookRuleParserTests.testSfacgChapterListURLOnTheWorkPageAndChaptersOnTheCatalogPage`（作品页 → `MainIndex/`；目录页 8 章；正文 ≥ 12 段）、
  `BookSiteRuleValidatorTests.testChapterListURLPairsOnlyWithChapterRule`；App `BookSourceRuntimeEndToEndTests.sfacgChaptersLiveOnTheCatalogPageOneHopAfterTheWorkPage`
  （列表 20 本、取页序列「作品页 → 目录页」、详情 8 章、正文、manifest 8 项）。夹具 `sfacg-catalog.json` 先取自规则仓库固定输入链的编译产物，真跑产出后替换。
- **段落选择器相对容器**：Core `parseTextContent` 在容器元素上 `select(paragraph)`，容器之外的祖先不可见；引擎侧已把 `div.yuedu > div p` 这类
  抄了容器路径的答法归一为 `p`、重放改在脱离副本上 select（规则仓库设计书 6.1 更正 9）——这条差异是 Core 夹具测试先逮到的，App 侧不改语义。
## 十八、站点书打开一章就把全书逐章取页 + 作品页封面被 ATS 拒

- **成因一（Readium 预加载永不停止）**：`ReadiumSitePublicationBuilder` 手建的 `Publication` 没有 positions 服务，`positionsByReadingOrder()` 退到
  `positionsFromManifest` → 每章一个**空**数组；`EPUBNavigatorViewController` 用 `!positionsByReadingOrder.isEmpty` 判 `hasPositions`，外层非空即真；
  `PaginationView.scheduleLoadPages` 按「后 6 前 2 个 position」递减，每个 spread 贡献 0，永远凑不满，直到书头书尾——每章一个 WebView、一次取页。
  所有站点文字书都受影响（biquhua 同样）；本地 EPUB 走 Streamer 自带 positions，不受影响。
- **修法一**：文字书出版物带 `InMemoryPositionsService`，每章 1 个 position（`position = i + 1`、`totalProgression = i / 章数`）；预加载回到前 2 章、后 6 章。
  有声作品走 `AudioNavigator`，不加。固定输入：`BookSourceRuntimeEndToEndTests.biquhuaTextBookFlowsFromListToPublication` 断言 112 章各 1 个 position。
- **成因二（封面绕过共享图片通道）**：sfacg 桌面列表页封面是 `http://`；列表网格走共享 `CoverImageView`（http → https 候选、带 Referer）所以有图，
  `BookSiteDetailView` 头部与 `AudiobookPlayerView` 用系统 `AsyncImage` 直连，被 ATS 拒。
- **修法二**：两处改用 `CoverImageView`，不开全局 ATS 例外（与第十七节跳转升级、第十六节 mp3 同一纪律）。
## 十九、站点书展示标题：列表标题与详情标题互相包含时取较短的

- **成因**：`BC-BOOK-050` 合同下详情字段在**目录页**（`m.sfacg.com/i/N/`）上取，而目录页上**没有任何元素的文字是书名**（无 h1–h3、无 og:title），
  引擎只能学到 `<title>`（run9 / run10 同为 `title` 选择器）。干净书名只在作品页 `ul.book_info span.book_newtitle` 与列表条目里。
- **为什么不是「优先用列表条目标题」**：第十五节已按用户裁决改为用 manifest 标题——biquhua 列表条目带分类前缀「[玄幻]普罗之主」、详情是「普罗之主」。
  两个站方向相反，单边优先必然弄坏另一个。
- **判据**：`SiteBookTitle.preferred(itemTitle:detailTitle:)`（`Application/UseCases/Book/BookPublicationAssembler.swift`）——两串去空白后，
  一个包含另一个取较短的；互不包含用详情标题；任一边为空取另一边。三站实际形状：biquhua → 「普罗之主」、sfacg → 「大傩」、loyalbooks 两边相同。
  不认站点、不认后缀词表。代价：详情标题比列表多出有用信息（如「大傩（第二部）」）时会取到较短的列表标题。
- **落点**：`BookSiteDetailViewModel.displayTitle`（导航栏与头部）、`BookReaderViewModel.openSite`（`loadedTitle`）。规则、引擎、服务器不动。
- **固定输入**：`BookSourceRuntimeEndToEndTests.siteBookTitlePrefersTheContainedTitle`（三站形状 + 互不包含 / 空值）、
  sfacg 端到端用例加断言（展示标题含书名、不含「目录列表」「SF轻小说」）。
## 二十、正文开头一段被丢 + 网页端没有正文的章节只显示标题

- **修法一（BrowseCraftCore，规则不动）**：段落规则是纯 CSS 选择器（无 functions / param / regex / replacement / fallback）时，
  经 `HTMLDocumentParsing.orderedTextBlocks` 按子节点文档顺序取块：直接子级非空裸文本、匹配选择器的元素各一块，
  含匹配元素的包裹层向下展开，其余元素（菜单、广告块）忽略。其他段落规则走原路径。biquhua 是 `lineBreaks`，不经过此路径。
  固定输入：Core `testSfacgChapterListURL…`（首段 = 「“求求你，救我，我真的已经……”」、无「上一章 / 下一章」）、`testElementsSegmentationKeepsBareTextInDocumentOrder`。
- **修法二**：Core 新增 `SourceRuntimeError.emptyContent(chapterURL:)`；Runtime `loadText` 拼页后 0 段即抛；
  `SiteBookChapterContainer` 接住它渲染说明页（章节标题 + `book_reader_chapter_no_web_content`：「这一章在网页上没有正文。站点可能只在自家 App 内提供这部作品的内容。」）。不认站点。
  固定输入：App `emptyChapterContentRendersANoticeInsteadOfATitleOnlyPage`。
## 二十一、开书时作品页与目录页各取两遍

- **成因**：`BookFeatureFactory` 给详情页与阅读器各建一个 `LoadBookPublicationUseCase`，两边互不知情。
- **为什么不把出版物塞进 `SiteBookChapterSelection` 往下传**：它是 `navigationDestination(item:)` 与 `.id(selection)` 的键，必须 Hashable；
  出版物带内容取数闭包，不可 Hashable。
- **修法**：`BookPublicationCache`（`Application/UseCases/Book/LoadBookPublicationUseCase.swift`）——工厂持有一份、传给两处用例；
  按「来源 id + 作品地址」为键，只缓存成功结果（详情页「重试」照常重取），5 分钟过期以跟上站点新增章节。
  不经过详情页的入口（历史里「继续阅读」）缓存未命中，照常取。
- **固定输入**：`BookSiteDetailViewModelTests.detailAndReaderShareOnePublicationLoad`（详情 + 阅读器共用缓存，作品页只取 1 次）、
  `publicationCacheExpiresAndSkipsOtherBooks`（同书二次命中、他源不命中、过期后重取）。
## 二十二、站点书搜索：由规则声明、与漫画 / 影视同一条合同

- **引擎侧**（fwq，同日）：核验关键词按条目取「列表标题与详情标题互相包含取较短」（`BC-SEARCH-004` 续，与第十九节同一条规则），零 token 测量 17 份真跑无误伤后落地。
- **Core**：`BookPageRule.url` 改可选；`BookSearchRule` 按引擎交付形状建模（`url` 带 `{keyword}`、`method`、`keywordEncoding`、`item`（引擎键名，不是 `itemRule`）、`fields`、`listRuleRef`、`pagination`、`request`）；
  校验器认 `type="search"` 页（只要求 `ruleRefs.search` 可解析），并校验搜索规则（`url` 含 `{keyword}`；`listRuleRef` 可解析，或自带 `item + fields.title/detailURL`）。
- **Runtime**：`BookSourceRuntime: SourceSearchRuntime`。`supportsSearch` = 存在 `type="search"` 页且其引用可解析；`search()` 把关键词按 `keywordEncoding` 编进 `{keyword}`
  （复用 `VideoSourceListLoader.searchURL`），第 N 页要 `pagination.urlTemplate`；条目取法借 `listRuleRef` 目标的 `itemRule / fields`（自带的覆盖），解析与输出映射复用 `loadList`。
  `page(for:)` 无 pageID 时取第一页**列表页**——搜索页与列表页并列写在 `pages[]`，不能拿到搜索页。
- **App**：`LibrarySearchView` 的结果点击按 kind 分流——读书 kind 进 `BookSiteDetailView`（此前无条件走漫画目的地，与 2026-09-13 漫画搜索的同型问题）。
- **固定输入**：Core `testSearchPageAndSearchRulesImport` / `testSearchRuleWithoutKeywordPlaceholderOrDanglingRefsIsRejected`；
  App `biquhuaSearchIsDeclaredByRuleAndParsesTheResultPage`（夹具 `biquhua-catalog-search.json` 按引擎交付形状构造 + `biquhua-search-mihunzhen.html` 真实结果页：1 条「[历史]迷魂阵」→ `/book/130/130817/`；
  列表仍落列表页；未声明搜索的 catalog 不支持；第 2 页无模板抛错）。
## 二十三、站点书进 History 页：与漫画、视频同列

- **现状**：批次 C 时用户裁决 B2「History 页不纳入书籍」（第十节）。站点书只有续读位置表 `book_reading_progress`（作品标识 + Locator + 时间），
  没有书名、来源、封面、章节，History 页拼不出一行，也重建不出阅读器的打开参数。本节按用户新裁决推翻 B2。
- **写入点**：`BookReaderViewModel`（注入 `SaveBookReadingHistoryUseCase`，缺省 nil）。站点书打开成功写一次；之后每次落进度（节流 1 秒、离开阅读器 `flush`）同步 upsert，
  章节取当前 Locator 所在的那一章（对法与详情页找续读章节相同：相对 href、补前导斜杠、或有声章节的远程地址），还没有位置时记第一章。**本地导入书不写**（入口已藏）。
- **展示与重开**：`ReadingHistoryEntry.Kind.book`，行标题 = 书名、副标题 = 最后读到的章节、图标 `book`。点开进与 Library 相同的 `BookReaderView`，
  主体由 `SiteBookChapterSelection(history:source:)` 重建——**不带章节**，阅读器按续读位置接着读（没有续读位置才从第一章开始）；来源取当前来源，没有则取快照。
  左滑删除只删历史行，**不删续读位置与书签**（从目录再点开仍接着读）。
- **账户合并**：`GRDBAppUserIdentityAdoptionStore` 的历史计数与合并复制加上这张表（同键保留较新的 `visitedAt`，与漫画历史同法）。历史表不进 CloudKit，与其它历史表一致。
- **固定输入**：`GRDBBookRepositoriesTests.bookReadingHistoryIsOnePerBookAndDeletingItKeepsProgress`（同书二次保存只更新一行、按访问时间倒序、历史用例并列出 `.book`、删除后续读位置仍在）；
  `BookReaderViewModelTests.openingSiteBookRecordsOneHistoryRowThatFollowsTheChapter`（loyalbooks 夹具：打开记第一章、换到第 3 章 flush 后同一行更新、从历史重建的作品标识不变）；
  `AppDatabaseSchemaSnapshotTests` 快照加一表一索引。