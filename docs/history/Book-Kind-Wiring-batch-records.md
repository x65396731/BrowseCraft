# 读书 kind App 侧接线：批次落地记录与实测纪事

本文属 H 类（`BCA-DOC-009`），**只追加，不修改**，不构成生产约束，不得被引用为实施依据。
内容是 [读书 kind App 侧接线](../design/Book-Kind-Wiring-Design.md) 在 2026-09-14 ~ 09-16 分批落地时的
过程记录：批次 A / B / C 的逐仓改动表、模拟器全流程走查，以及各节里按 `BCA-DOC-007` 三分法
搬出的 `现象` / `模拟器实测` / `验证` / `引擎真跑逮到的形状` 条目。逐字保留，未改写。

各条对应的当前状态见 [STATUS.md](../STATUS.md) 第 1 节；仍然有效的判据、修法与固定输入留在设计文档原节。

## 二、已核对的现状（2026-09-13，只读）

| 处 | 现状 | 对 book 的含义 |
|---|---|---|
| APIKit `PortalRuleGenerationSourceKind` | `video / comic` 封闭枚举（注释仍写服务端是 `Literal["video","comic"]`，已过期） | 加 `book`，注释改 |
| APIKit `BrowseCraftCatalogSourceKind` | `comic / rss / video` 封闭枚举，`[CatalogSourcePayload]` 整表 `decode` | 加 `book`；同时把未知 kind 改为**逐条跳过**而不是整表失败 |
| APIKit `PortalRuleGenerationCatalogSource.kind` | `String` | `/outcomes` 与 200 cached 响应遇到 book **不会**解码失败 |
| App `LoadVideoGenerationOutcomesUseCase` / `CreateVideoGenerationTaskUseCase` | `CatalogSourceKind(rawValue:)` 守门，未知 kind 分别「原样返回」与 `reusedRuleKindUnsupportedCode` | 旧版 App 提交过 book 的用户看到成功结果但无法导入；不崩 |
| Domain `CatalogSourceKind` | `comic / rss / video` | 加 `book` |
| Domain `SourceConfiguration` | `comic(ComicSourceConfiguration) / rss / video / plugin`，间接枚举，逐 key 解码 | 加 `book(BookSourceConfiguration)` 与 `book` 编码键 |
| Core `SourceRuntimeKind` | `comic / rss / video / plugin`，旧值 `rule` 兼容为 comic | 加 `book` |
| Core 规则模型 | `ComicSiteRuleV2`（V1→V2 迁移 + 校验，Core internal 构造） | 新建 `BookSiteRuleV2`：无迁移器，只有严格校验器 |
| Runtime | `Comic/`（Factory、Mapper、List / Detail / Reader / Search Loader、API 解析） | 新建 `Book/` 同形；reader loader 产出「段落数组」或「音频地址数组」 |
| App 入口 | `SourceImportOptionKind.comicSource / videoSource / rssFeedURL / scriptSource`；`AddSourceView` 按 kind 分流到 `VideoGenerationInputView(sourceKind:)`；`RuleGenerationSourceKind = video / comic` | 加 `bookSource` 与 `.book`，复用同一输入视图与预检（预检是中性的，`BC-PREFLIGHT-047`） |
| App 其余 `case .comic` 分流点 | 17 个文件（`SourceRuleEditorService` 4 处、`SourceDebugView` / `LibrarySourceLoginState` / `HistoryEntryRowView` / `FavoritesView` / `FavoriteContentItem` 各 2 处，`CatalogSourceMaterializer`、`CatalogSourceListView`、`RuntimeSourceImportView`、`HistoryView`、`ValidateSourceListLoadUseCase`、`ToggleFavoriteUseCase`、`ReadingHistoryUseCases`、`DiagnosticEnums`、`APIKitVideoGenerationTaskClient`、`VideoGenerationInputView` 各 1 处） | 枚举加 case 后由编译器逐处报缺，按清单补；Domain 3 文件、Runtime 3 文件同理 |
| Readium | 依赖已入库，`Check SwiftSoup Override` 预构建阶段已加；**从未整包 build** | 任何 Feature 工作之前先 build 一次，并真机复核影视线与漫画线 |

两份真实 catalog 可直接作 Core 固定输入：规则仓库 `prototype-output-book-p5-biquhua-openai-run3-20260913/…/book/catalog.json`（`text-dom` / `lineBreaks`、章节 `li.col-md-3 > a`、`site.loginURL`）与 `…-loyalbooks-openai-run6-20260913/…/book/catalog.json`（`audio-media`、列表分页模板 `?page={page}`、17 条 mp3）。

## 八、批次 A 落地记录（2026-09-14）

| 仓库 | 改动 | 验证 |
|---|---|---|
| BrowseCraftAPIKit | `PortalRuleGenerationSourceKind.book`；`BrowseCraftCatalogSourceKind.book`；目录列表改为**逐条解码、未知 kind 跳过并记录**（`BrowseCraftSourceCatalog.decode` 返回 `skipped`）；目录请求显式带 `?kinds=comic,rss,video,book`（PortalCore §14.6，旧服务端忽略该参数） | `swift test` 33 项，含新增 3 项 |
| BrowseCraftCore | `SourceRuntimeKind.book`；`SourceDefinition.book`（缺省 nil）；`BookSiteRule` 模型（原生 V2、三变体）与 `BookSiteRuleValidator`（BC-BOOK-001 ~ 008 的结构与引用约束，按 JSON path 报问题）；两份真实 catalog 作固定输入 | `swift test` 225 项，含新增 7 项（两份真实 catalog 原样通过，六类反例各一） |
| BrowseCraftDomain | `CatalogSourceKind.book`；`SourceConfiguration.book(BookSourceConfiguration)`（编码键 `book`）；`SourceDefinitionMapper` 的 book 分支 | `swift build`（包无测试目标） |
| BrowseCraftRuntime | `SourceRuntimeFactory` 对 book **明确抛不支持**（批次 B 接入）；列表映射暂按文章形态 | `swift build` |
| BrowseCraft | `RuleGenerationSourceKind.book` 与生成客户端映射；`CatalogSourceMaterializer` 的 book 分支（经 `BookSiteRuleValidator`）；诊断枚举加 `book`；调试视图、规则编辑服务、登录状态、目录列表、列表校验、测试解析器各补 book 分支；`book_preflight_navigation_title` 文案 | 全量测试 + 边界脚本 |

**这一批之后 App 能做什么**：解码含 book 的公共目录（旧版整表失效的问题已闭合）、把 book catalog 物化成 `Source`、向服务器提交 `sourceKind: book` 的生成请求（入口在批次 C）。
**还不能做什么**：按规则取正文 / 音频（Runtime 批次 B）、显示书籍入口与阅读（批次 C）。

## 九、批次 B 落地记录（2026-09-14）

| 仓库 | 改动 |
|---|---|
| BrowseCraftCore | `DefaultBookRuleParser`（Parsing/Book）：走与 comic / video 同一条内部 ExtractRule 管线；`parseList`（title / detailURL 必填，分页模板算下一页、空页停）、`parseDetail`（title 必填，chapterRule 章节去重）、`parseTextContent`（`elements` 取段落元素文本；`lineBreaks` 取容器 HTML 按 `<br>` 切、去标签、解实体）、`parseMedia`。`SourceBookContentRuntime` 合同（`SourceBookContentInput / Output`，`SourceBookChapterContent = text(title, paragraphs) | audio([items])`）。固定输入：两站五份 HTTP 形状语料（biquhua 30 条 / 112 章 / ≥12 段；loyalbooks 分页 `?page=2` / 17 条 mp3）。 |
| BrowseCraftRuntime | `BookSourceRuntime` + `BookSourceRuntimeFactory`（Book/）：`loadList`（page → list 规则，第 N 页用分页模板）、`loadDetail`（chapterRule；chapterAPI 抛不支持）、`loadBookContent`（text-dom 按 `content.next` 逐页拼、最多 50 页；audio-media 出边是音频地址就不取页，否则按 `media` 规则取；text-api / mediaAPI 抛不支持——无语料）。`SourceRuntimeFactory` 加 `bookSourceRuntimeFactory` 参数。 |
| BrowseCraft Application | `BookPublicationManifest`（纯值，BC-BOOK-012 对应表）、`BookPublicationAssembler`（章节出边是音频 → 有声出版物；否则正文出版物，href `chapters/0001.xhtml`）、`BookXHTMLRenderer`（转义 + 包装）、`LoadBookPublicationUseCase`（详情 → manifest + 按需取内容的 provider）。 |
| BrowseCraft Infrastructure | `ReadiumSitePublicationBuilder`：manifest → `Publication(manifest:container:)`；`SiteBookChapterContainer` 只承载正文章节，每个 href 是按需取正文并装 XHTML 的 `DataResource`；音频章节是远程 href，`conformsTo: [.audiobook]`。 |
| BrowseCraft 组合根 | `SourceRuntimeComposition` 装配 `BookSourceRuntimeFactory(pageContentLoader:defaultUserAgent:)`。 |

验收：`BookSourceRuntimeEndToEndTests`——真实 catalog → Source → Runtime（网页由夹具桩）→ 详情 / 章节 / 正文或音频 → manifest → Publication，两站各一条；正文资源读出来是带 `<p>` 的 XHTML，mp3 出边不取页。
**还没有**：Features 入口（批次 C）；站点书的进度 / 书签落库（本地书三张表的作品标识扩展，第六节第 3 条）；listAPI / chapterAPI / text-api / mediaAPI（无语料）。

## 十、批次 C 落地记录（2026-09-14）

| 处 | 改动 |
|---|---|
| 添加来源 | `SourceImportOptionKind.bookSource`（`defaultOptions` 第三项，`.html` / `.book`）；`AddSourceView` 的「Books」入口走同一个 `VideoGenerationInputView(sourceKind: .book)`；`RecommendSourceImportOptionUseCase` 的 book 推荐。 |
| Library | 读书来源的列表复用漫画网格；点开走 `LibrarySiteBookDestination` → `BookSiteDetailView`（头部、开始 / 继续阅读、章节列表）；章节推入共用的 `BookReaderView`（推入方式见第十二节的修正——批次 C 原写法是 `NavigationLink(value: LibraryBookRoute.siteChapter(...))`，模拟器实测栈序错乱后改成详情页自有的 item 式推入）。 |
| 阅读器 | `BookReaderViewModel` 改为按 `BookReaderSubject`（`.local(LocalBook)` / `.site(SiteBookChapterSelection)`）打开；站点书：`LoadBookPublicationUseCase` → `ReadiumSitePublicationBuilder` → 起点 = 点开的章节，否则续读位置。有声作品先抛「播放器在后续批次」。 |
| 作品标识 | `SiteBookIdentity.bookID(sourceID:detailURL:)`（SHA-256 前 16 字节，v5 版本位）；迁移 `v4.book-progress-detached-from-local-books` 重建进度与书签两张表去掉对 `local_books` 的外键（保留对 users 的级联）；`DeleteLocalBookUseCase` 显式删进度与书签。 |
| 装配 | `BookFeatureFactory` 拿 `SourceRuntimeResolving`；`LibraryContentViewModelFactory` 加 `makeBookSiteDetail` / `makeBookSiteReader`。 |

验收：视图模型固定输入（作品标识稳定、详情列 112 章并按续读位置定起点、阅读器按主体打开站点书到 ready）；全量测试 + 边界脚本；模拟器走通 添加来源 → 生成 → 目录 → Library → 详情 → 阅读 需要真实生成任务，**真机验收由用户做**。
**还没有**：站点有声作品的播放器；listAPI / chapterAPI / text-api / mediaAPI（无语料）；History 页纳入书籍（用户裁决 B2 不纳入；**2026-09-16 用户改裁决纳入，见第二十三节**）。

## 十一、模拟器全流程走查（2026-09-14）

- 预检通过后提交生成要求 Portal 登录（Apple 登录），模拟器无会话，生成路走不通；用户裁决改走**发布路**：把规则仓库第三次真跑的 biquhua catalog 经 `POST /catalog/sources` 发布进公共目录（服务器已部署 `kinds` 过滤，旧版缺省仍 26 条；`kinds=book` 1 条；全集 27 条）。
- 逮到一处：App 取公共目录的 `LoadCatalogSourcesUseCase` 自己拼地址、自己解码，**没走 APIKit**——批次 A 加在 `PortalCatalogAPI` 上的 `?kinds=` 与宽容解码都没覆盖到它，服务器访问日志里 App 的请求不带参数、缺省拿不到 book。修法：缺省地址带 `kinds=comic,rss,video,book`（用 switch 穷举 `CatalogSourceKind`，新增 case 编译期报缺）；解码时未知 kind 逐条跳过并记日志。固定输入 `LoadCatalogSourcesUseCaseTests`。
- 走查结果（模拟器 iPhone 16 Pro，服务器目录）：目录顶部出现「笔趣阁 · 书籍」→「+」添加成功 → Library 书籍网格出封面 → 详情页（标题、作者「沙拉古斯 著」头部未显示但正文出版物标题带「[玄幻]」前缀、112 章）→ 点章节 → 阅读器渲染正文（章标题 + 段落）→ 左滑翻页（一章三页）→ 返回详情出现「继续阅读」与章节行书签标记 → 「继续阅读」落回第三页。**这是模拟器、家用网络出口的结果；真机验收仍由用户做。**
- 走查中逮到并已修：章节推入的栈序错乱（第十二节）。
- 走查中看见、没动：biquhua 正文里带站点自己的分页标记「第(1/3)页」（规则 `content.text` 把它当段落取了，属规则侧内容清洗，回 fwq 处理）；阅读器标题用的是作品原标题「[玄幻]普罗之主」，详情页用的是清洗后的 manifest 标题，两处不一致。

## 十二、章节推入的栈序修正（2026-09-14，模拟器实测）
- **现象**：详情页点章节后，屏幕上还是详情页（返回键变成「返回」、底栏消失）；按返回反而看见阅读器，再按一次才回 Library。栈变成了「Library → 阅读器 → 详情」。
## 十三、章内分页的停止判据（2026-09-14，真机倒查）
- **现象**：真机上 biquhua 每章只有第一页（站点把一章切成 3 页，页尾「第(1/3)页」）。规则侧 `content.next` 为 null 是主因（引擎按链接文字「下一章」拒了它，在 fwq 修），但 App 侧还有一处一旦规则给了 `next` 就会暴露的缺口。
## 十四、book 列表分页在 ViewModel 被 kind 门挡住（2026-09-14，模拟器复验）
- **现象**：规则已带分页模板、Runtime 报出 `nextPage=2`，库页却不挂触底哨兵、不显示「第 1 页」状态条。
- **模拟器复验（iPhone 16 Pro，服务器目录，家用出口）**：删掉重加笔趣阁后，榜单滑到底自动取 `all_0_2.html`、`all_0_3.html`（30 → 60 → 90 条，状态条「第 3 页」）；打开《绍宋》任一章，正文取页序列为 `X.html → X_2.html → X_3.html` 后停，相邻章节各自独立取页，没有一章吞下一章。
## 十六、站点有声作品的播放器（2026-09-14，用户裁决「先照抄，接起来再说，后面再改 UI」）
- **模拟器实测（iPhone 16 Pro，服务器目录，家用出口）**：loyalbooks catalog 发布进公共目录（用户裁决）→ 添加 → 32 本出封面 → 《Tom Sawyer》17 章 →
  Start Listening → 起播 00:36 / 26:38 → 下一章 03–04 → 退回详情「Continue Listening」带续听标记 → 再进从 01:05 继续。
## 十七、`chapterListURL`：章节列表在从作品页单跳到达的目录页（2026-09-14 立项，用户裁决「按设计实施」，同日实施）
- **引擎真跑逮到的形状（2026-09-14 第三次真跑）**：引擎与 App 都用 iPhone UA，sfacg 把 `book.sfacg.com/Novel/N/` 302 到移动站 `m.sfacg.com/b/N/`，
  目录 `/i/N/`、章节 `/c/N/`。规则因此是在移动站上学的：`chapterListURL` = `.book_Catalog > a:nth-of-type(2)`（相对**落点**解析，
  `document.finalURL` 是移动站地址）、`chapterRule.item` = `ul.mulu_list > a[href][href*='/c/']`、正文 `div.yuedu > div` + 段落 `p`。
  夹具切到 `sfacg-m-*`（引擎 UA `curl` 取得的移动站四页），`FixturePageContentLoader` 加 `redirects:` 模拟 302。
- **模拟器逮到的传输层缺口（2026-09-14）**：sfacg 把 `https://book.sfacg.com/Novel/N/` 302 到 **`http://`** 的移动站、再 301 回 https；
  引擎的 HTTP 客户端无 ATS 跟得过去，App 的 URLSession 在 http 那一跳被 ATS 拒（详情页「网络请求失败 … App Transport Security」）。
  处置与有声书 mp3 同一纪律：`AlamofireHTTPClient` 加 `httpsUpgradingRedirector`（Alamofire `Redirector(.modify)`），跳转目标是 http 就升成 https
  （站点本就在 https 上服务），不开全局 ATS 例外；单元测试 `AlamofireHTTPClientRedirectTests`。
- **模拟器**：sfacg catalog 发布进公共目录后走通：添加 → 列表 → 作品 → 章节 → 正文（见规则仓库 HANDOFF 0.0.A25 续五）。

## 十八、站点书打开一章就把全书逐章取页 + 作品页封面被 ATS 拒（2026-09-14，sfacg 真机日志倒查，用户裁决「两处一起修」）
- **现象（真机日志）**：点开一章后，从该章起按阅读顺序连续取几十到上百个 `m.sfacg.com/c/…`（38380 上百章），同时成批创建 / 销毁 WebContent 进程；
  作品页头部封面报 `NSURLErrorDomain -1022`（`http://rs.sfacg.com/…NovelCover…`）。
- **模拟器实测（iPhone 16 Pro，本机家用出口）**：sfacg《大傩》（7 章）点开第七章 → 章节取页恰为 3 次（第五、六、七章），修前应为 7 次；正文正常显示；
  作品页封面出图、日志无 `-1022`。全量 506 / 89 过，架构边界干净。**真机待用户验。**

## 十九、站点书展示标题：列表标题与详情标题互相包含时取较短的（2026-09-15，用户裁决「互相包含取较短」）
- **现象**：sfacg 详情页与阅读器标题显示「大傩目录列表 - 小说频道 - SF轻小说」。
- **验证**：全量 507 / 89 过、架构边界干净；biquhua 端到端用例加断言（夹具真实列表条目标题带前缀、展示标题 = 「普罗之主」），套件 8 / 8 过。
  模拟器（iPhone 16 Pro，本机家用出口）：sfacg《在鱼塘钓鱼的两人》详情页导航栏 / 头部与阅读器标题都是干净书名（修前是「…目录列表 - 小说频道 - SF轻小说」）。
  biquhua 未在模拟器上看（来源位 1/1 被 sfacg 占用，换源要删来源并清历史），以夹具断言代替。**真机待用户验。**

## 二十、正文开头一段被丢 + 网页端没有正文的章节只显示标题（2026-09-15，sfacg 真机「只有标题没有内容」倒查，用户裁决「App Core 补取裸文本」「显示空章说明」）
- **现象一（开头丢段）**：sfacg 正文页 `div.yuedu > div` 里首句是第一个 `<p>` 之前的裸文本；规则 `segmentation: elements` + `paragraph: p`，
  Core 只取 `p`。已测 6 份正文页（run10 采集 4、语料 1、真机书 784586 一章）**6 份都丢开头**（「——2025年4月1日，魔女岛监狱宅邸——」「“求求你，救我……”」等）。
- **现象二（空章）**：《她靠马甲杀回，权贵圈争着喊夫人》（767172，签约作品）每章移动站页约 9.8KB、正文容器为空；
  桌面章节页 `#ChapterBody` 只有「全新的沉浸式互动小说…只能在APP上观看哦,扫码下载APP观看吧~」。不是付费、不是登录——**站点只在自家 App 内给正文**，任何规则都取不到。
  此前 Runtime 交出 0 段正文，阅读器只渲染章节标题，用户无从知道原因。
- **验证**：Core 232 过（4 跳过）、Runtime 编译过、App 508 / 89 过、架构边界干净。模拟器未走（开屏「跳过」需人工）；**2026-09-15 真机通过（用户确认）**：
  784586 首章开头是「看见面前手的那瞬间……」；767172 章节显示说明页。

## 二十一、开书时作品页与目录页各取两遍（2026-09-15，真机日志，用户裁决「做这一项」）
- **现象**：每次打开站点书，日志里作品页（`book.sfacg.com/Novel/N/`）与目录页（`m.sfacg.com/i/N/`）各出现两次——
  详情页 `BookSiteDetailViewModel.load` 取一遍，点章节进阅读器 `BookReaderViewModel.openSite` 又原样取一遍。
- **验证**：全量 510 / 89 过、架构边界干净。**2026-09-15 真机通过（用户日志）**：783159 开书，作品页 `book.sfacg.com/Novel/783159/` 与目录页 `m.sfacg.com/i/783159/` 各 1 次，随后只取章节。

## 二十二、站点书搜索：由规则声明、与漫画 / 影视同一条合同（2026-09-15，用户问「设计书里没有搜索能力吗？book 应该和漫画影视一样才对」，裁决「两侧一起做」）
- **核实**：规则仓库设计早有（`BC-BOOK-045`：搜索发现与验证三 kind 共用，book 只投影 `ruleSets.searchRules[]` + 一页 `type="search"`），
  三个书站的真跑也都走了搜索发现，只是没有一次验证通过（biquhua 核验关键词带分类前缀「[历史]迷魂阵」站内搜 0 条；loyalbooks / sfacg 结果页 JS 渲染）。
  App 侧则从来没接：`BookSourceRuntime` 写死 `supportsSearch: false`、无 `search()`；更早一格，Core `BookPageRule.url` 必填、页型只认 `list`——
  引擎一旦真的写出搜索页（无 url），整份 catalog 在 App 会解码失败。
- **验证**：Core 234 过（4 跳过）、Runtime 编译过、App 全量见提交说明。**未真机**：要等 biquhua 用新判据真跑出带搜索的 catalog、替换线上规则后，由用户真机验搜索。

## 二十三、站点书进 History 页：与漫画、视频同列（2026-09-16，用户「book 的浏览记录目前不在历史里再次打开，我需要你做成和漫画、视频一样的」）
- **数据**：迁移 `v5.book-reading-history` 新表 `book_reading_history`，主键 `(userID, sourceID, detailURL)`——**一本书一条**，与漫画在历史页按作品聚合后的形状一致；
  作品身份与 `SiteBookIdentity`（sourceID + 作品地址）同源。列：`bookItemID`、`bookTitle`、`coverURL`、`chapterTitle`、`chapterURL`、`visitedAt`、`sourceSnapshotJSON`（来源被删后仍能打开，与漫画 / 视频历史同一个兜底）。
  续读位置仍只在 `book_reading_progress`，历史表不重复存 Locator。索引 `(userID, visitedAt DESC)`。外键只到 `users`（级联）。
- **验证**：iPhone 16 Pro 模拟器（iOS 18.5）App 全量 517 项 / 89 组 + XCTest 39 项全过，架构边界干净。**未真机**：读一本站点书 → History 出现该书与最后读到的章节 → 点开从续读位置接着读 → 左滑删除后从目录再点开仍接着读，由用户真机验。

