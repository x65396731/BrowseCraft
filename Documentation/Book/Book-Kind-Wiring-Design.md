# 读书 kind（book）App 侧接线（立项，待拍板）

更新时间：2026-09-13
状态：**批次 A、B、C 已落地（2026-09-14）**；有声作品的播放器与四个接口变体另立项；顺序与发布策略已由用户裁决（第四、五节）。本地文件导入线的入口已按用户裁决藏起（[本地书籍导入](Local-Book-Import-Design.md) 第八节），其阅读器 / 书签 / 三张表留给批次 B / C 复用
影响范围：BrowseCraftAPIKit、BrowseCraftDomain、BrowseCraftCore、BrowseCraftRuntime、BrowseCraft 五个仓库；影视线与漫画线代码零改动
前置：服务器接线已部署（PortalCore `b9fc2ff`，2026-09-13 深夜），`POST /v1/rule-generations` 已接受 `sourceKind: book`；Readium 3.11.0 依赖已入库（BrowseCraft `7ad27044`），**首次整包 build 已于 2026-09-13 深夜通过**（`xcodebuild -scheme BrowseCraft` 模拟器 iPhone 16 Pro，0 error；影视线与漫画线的真机复核仍待用户）

## 一、结论

1. book 是 App 里的第四种 `SourceRuntimeKind`（comic / rss / video / plugin 之后），按现有 comic 的分流模式扩展，不在通用执行器里加 kind 特判（AGENTS.md）。
2. 规则合同以规则仓库 `docs/rules/book-catalog-profile.md`（`BC-BOOK-001` ~ `BC-BOOK-012`）为准：外层 `id / name / baseURL / kind="book" / ruleJSON`，内层**只有原生 V2**（`version=2`、`site`、`sharedRequest`、`pages[]`、`ruleSets{listRules, detailRules, readerRules, searchRules?}`），没有 V1 兼容层，Core 不得为它虚构 `list / detail / gallery` 顶层字段。
3. 终端层与漫画不同：reader 规则每条恰好一个 `variant`（`text-dom | text-api | audio-media`）与 `contentType`（`text | audio`）。App 把一部作品装成一份 RWPM（`BC-BOOK-012`）喂 Readium：文字走 EPUB Navigator（`readingOrder[].type = text/html`，正文由 App 按 reader 规则取容器内段落装成 XHTML），有声走 Audio Navigator（远程 mp3 href）。CBZ 分支不接。
4. **兼容硬约束**：目录列表接口在 APIKit 是整表解码且 `BrowseCraftCatalogSourceKind` 是封闭枚举（`Catalog/BrowseCraftCatalogAPI.swift`），App Domain 的 `CatalogSourceKind` 同样封闭——只要目录里出现一条 `kind: book`，**所有旧版 App 的整个目录列表都解码失败**。因此 book catalog 在 App 侧宽容解码版本上线之前**不得发布**到 `/catalog/sources`（第五节）。

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

## 三、范围与分批（每批单独拍板、单独提交、单独推送）

**批次 A：合同与枚举（无 UI，可先于 build）**
- APIKit：`PortalRuleGenerationSourceKind.book`；`BrowseCraftCatalogSourceKind.book` + 目录列表未知 kind 逐条跳过（记录被跳过的 id 与 kind，不静默）；用例覆盖「列表里混入未知 kind 时其余条目仍可用」。
- Domain：`CatalogSourceKind.book`、`SourceConfiguration.book(BookSourceConfiguration)`（`rule: BookSiteRuleV2`、`schemaVersion`、`packageMetadata`、`isEditable`，与 comic 同形）。
- Core：`SourceRuntimeKind.book`；`BookSiteRuleV2` 模型（`site / sharedRequest / pages / ruleSets`，reader 规则为三变体的封闭枚举）与校验器（键集、枚举、`variant` ↔ `contentType` 配对、页引用可解析、`BC-BOOK-003` 字段归属）；两份真实 catalog 作解码固定输入。
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

## 四、顺序（用户 2026-09-13 裁决：先本地文件导入闭合阅读器）

交接单第五节建议**先做本地文件导入把阅读器与书签闭合，再接站点抓取**。**用户裁决按交接单的顺序：先用本地 EPUB / M4B 把 Readium 阅读器与 `Locator` 书签跑通，站点抓取路后补。**因此实施顺序改为：① 首次整包 build（Readium 链接进来后从未 build 过）→ ② 本地文件导入（另出设计节：文件来源、`Publication` 打开、EPUB 与 Audio Navigator、书签落库）→ ③ 本文批次 A → B → C。批次 B 的装配器先接本地 `Publication`，站点路复用同一个 Navigator 与书签模型。

## 五、兼容与发布策略（用户 2026-09-13 裁决：不发布 + 服务器加 `kinds` 过滤）

目录列表接口在旧版 App 里整表解码、kind 封闭，book 一旦发布即让旧版目录整体失效。三条路：

1. **不发布**：book catalog 只经生成任务的 `/outcomes` 与 200 cached 响应到达提交它的用户（那两条路 kind 是字符串，旧版不崩），目录接口不放 book，直到批次 A 的宽容解码版本上线并稳定。
2. **服务器过滤**：PortalCore 目录接口加 `kinds` 查询参数，缺省只返回 `video, comic`；新版 App 显式带 `kinds=video,comic,book`。改动在 PortalCore（无鉴权端点，属用户有意设计，参数不改变这一点）。
3. **两者都做**：先 1 后 2。

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
**还没有**：站点有声作品的播放器；listAPI / chapterAPI / text-api / mediaAPI（无语料）；History 页纳入书籍（用户裁决 B2 不纳入）。

## 十一、模拟器全流程走查（2026-09-14）

- 预检通过后提交生成要求 Portal 登录（Apple 登录），模拟器无会话，生成路走不通；用户裁决改走**发布路**：把规则仓库第三次真跑的 biquhua catalog 经 `POST /catalog/sources` 发布进公共目录（服务器已部署 `kinds` 过滤，旧版缺省仍 26 条；`kinds=book` 1 条；全集 27 条）。
- 逮到一处：App 取公共目录的 `LoadCatalogSourcesUseCase` 自己拼地址、自己解码，**没走 APIKit**——批次 A 加在 `PortalCatalogAPI` 上的 `?kinds=` 与宽容解码都没覆盖到它，服务器访问日志里 App 的请求不带参数、缺省拿不到 book。修法：缺省地址带 `kinds=comic,rss,video,book`（用 switch 穷举 `CatalogSourceKind`，新增 case 编译期报缺）；解码时未知 kind 逐条跳过并记日志。固定输入 `LoadCatalogSourcesUseCaseTests`。
- 走查结果（模拟器 iPhone 16 Pro，服务器目录）：目录顶部出现「笔趣阁 · 书籍」→「+」添加成功 → Library 书籍网格出封面 → 详情页（标题、作者「沙拉古斯 著」头部未显示但正文出版物标题带「[玄幻]」前缀、112 章）→ 点章节 → 阅读器渲染正文（章标题 + 段落）→ 左滑翻页（一章三页）→ 返回详情出现「继续阅读」与章节行书签标记 → 「继续阅读」落回第三页。**这是模拟器、家用网络出口的结果；真机验收仍由用户做。**
- 走查中逮到并已修：章节推入的栈序错乱（第十二节）。
- 走查中看见、没动：biquhua 正文里带站点自己的分页标记「第(1/3)页」（规则 `content.text` 把它当段落取了，属规则侧内容清洗，回 fwq 处理）；阅读器标题用的是作品原标题「[玄幻]普罗之主」，详情页用的是清洗后的 manifest 标题，两处不一致。

## 十二、章节推入的栈序修正（2026-09-14，模拟器实测）

- **现象**：详情页点章节后，屏幕上还是详情页（返回键变成「返回」、底栏消失）；按返回反而看见阅读器，再按一次才回 Library。栈变成了「Library → 阅读器 → 详情」。
- **成因**：`LibraryView` 用 `navigationDestination(item:)` 推详情（与漫画同款），详情里的章节却用 `NavigationLink(value:)` 走栈根的 `navigationDestination(for: LibraryBookRoute.self)`。栈上没有显式 path 绑定时，value 式推入进的是栈的内部 path，item 式推入是独立的呈现元素，两者混用后 SwiftUI 把 item 式的详情重新排到了最上面。
- **修法**：与 `ComicDetailView` 同款——`BookSiteDetailView` 自己持有 `selectedChapter` 并声明 `navigationDestination(item:)`，章节行改成 Button 设值；`LibraryBookRoute.siteChapter` 删除，`LibraryView` 把 `makeBookSiteReader` 作为闭包传给详情页。行字用 `Color.primary` 压回正文色（List 里的 Button 标签缺省染 tint）。
- **对第八节结论的补充**：「多级 `navigationDestination(for:)` 必须在栈根声明一次」仍成立；本节补的是另一条——**同一条推入链上不要混用 value 式与 item 式**，一条链选定一种。

## 十三、章内分页的停止判据（2026-09-14，真机倒查）

- **现象**：真机上 biquhua 每章只有第一页（站点把一章切成 3 页，页尾「第(1/3)页」）。规则侧 `content.next` 为 null 是主因（引擎按链接文字「下一章」拒了它，在 fwq 修），但 App 侧还有一处一旦规则给了 `next` 就会暴露的缺口。
- **缺口**：`BookSourceRuntime.loadText` 按 `content.next` 逐页拼接，停止条件只有「指回已取过的页」与上限 50 页。biquhua 章内页与下一章共用同一个 `a#next`（文字一律「下一章」），末页的 `next` 指向下一章 `129024.html`——规则一给值，第 1 章会把后续章节一路吞到上限。
- **修法**：加第三条停止条件 `isInChapterPage(candidate, chapterURL:)`——候选地址必须是本章地址的**兄弟页**：同主机、同目录、同扩展名，末段 = 本章词干 + 非字母数字分隔符 + 页码（≥ 2）；本章地址自己已带页码时词干去掉「分隔符 + 页码」后算。与引擎 `_FUSED_PAGE_SEGMENT`（`BC-LIST-093`）同一形状。只看 URL 形状，不看链接文字。
- **不覆盖**：query 形的章内分页（`?page=2`）——首批语料没有样本，量到再加。
- **固定输入**：`BookSourceRuntimeEndToEndTests.biquhuaInChapterPagesAreJoinedAndStopAtNextChapter`（三页夹具 `biquhua-reader-110-129023{,-p2,-p3}.html` + 带 `next` 的 `biquhua-catalog-next.json`：拼接后段落多于单页、取页序列恰为三页、不取 `129024.html`）与 `inChapterPageGuardOnlyAcceptsSiblingPagesOfTheChapter`（十个形状用例）。

## 十四、book 列表分页在 ViewModel 被 kind 门挡住（2026-09-14，模拟器复验）

- **现象**：规则已带分页模板、Runtime 报出 `nextPage=2`，库页却不挂触底哨兵、不显示「第 1 页」状态条。
- **成因**：`LibraryViewModel.selectedSourceSupportsListPagination` 写的是 `kind == .video || kind == .comic`——09-12 从只认影视放宽到漫画时的形状，book 后来接入没跟上。
- **修法**：加 `.book`。固定输入 `LibraryViewModelTests.bookListAdvancesToTheNextPageWhenRuntimeReportsOne`（与漫画同款：第 1 页报 nextPage=2 → 触底取第 2 页 → 报 nil 即停）；`TestSourceRuntimeResolver` 补 `bookRuntimeFactory`，`Harness.makeBookSource()` 用 biquhua-catalog 夹具物化。
- **模拟器复验（iPhone 16 Pro，服务器目录，家用出口）**：删掉重加笔趣阁后，榜单滑到底自动取 `all_0_2.html`、`all_0_3.html`（30 → 60 → 90 条，状态条「第 3 页」）；打开《绍宋》任一章，正文取页序列为 `X.html → X_2.html → X_3.html` 后停，相邻章节各自独立取页，没有一章吞下一章。
- **待补的缺口**：规则目录里「已添加」的来源没有任何动作，服务器上更新了规则的用户拿不到新版本，只能删掉重加；应给已添加来源提供「更新规则」（同 id 再添加即覆盖本地规则，`AddCatalogSourceUseCase` 已支持）。

## 十五、页码标记清洗与阅读器标题（2026-09-14，用户裁决「App 拼页时剔除 + 统一标题」）

- **页码标记**：biquhua 每页正文首尾各一行「第(1/3)页」，规则 `content` 把它当段落。清洗放在 Runtime 拼页处（`joinedParagraphs(pages:)`），
  不放引擎：拼页时 App 知道「本章共 m 页、这段在第 k 页」，剔除条件是**整段只有「第 k/m 页」这一行且 k、m 与实际拼接页数对得上**，
  对不上（只取到一页、取页中途失败、正文原文提到「第 2/3 页」）原样保留。引擎侧要给规则 DSL 加剥除槽位、四处合同都要动，重得多。
- **阅读器标题**：此前用列表条目标题（带分类前缀「[玄幻]普罗之主」），详情页用 manifest 标题（详情规则清洗后「普罗之主」）。
  出版物加载后 `BookReaderViewModel.title` 改用 manifest 标题，加载前仍用列表标题占位。
- **固定输入**：`BookSourceRuntimeEndToEndTests.pageMarkersAreStrippedOnlyWhenTheyMatchTheJoinedPages`（七个形状 + 拼接）；
  三页拼接用例断言拼接后无标记、单页取法保留。

## 十六、站点有声作品的播放器（2026-09-14，用户裁决「先照抄，接起来再说，后面再改 UI」）

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
- **模拟器实测（iPhone 16 Pro，服务器目录，家用出口）**：loyalbooks catalog 发布进公共目录（用户裁决）→ 添加 → 32 本出封面 → 《Tom Sawyer》17 章 →
  Start Listening → 起播 00:36 / 26:38 → 下一章 03–04 → 退回详情「Continue Listening」带续听标记 → 再进从 01:05 继续。
- **固定输入**：`BookReaderViewModelTests.openingSiteAudiobookBuildsAnAudioNavigator`、`BookSourceRuntimeEndToEndTests`（音频 href 有资源、第 1 页用入口地址）、
  `SiteBookAudioHTTPClientTests`、`BookSiteDetailViewModelTests.returningToDetailRefreshesReadingProgressWithoutReloading`。
- **后面再改的**：界面样式；倍速与偏好入口（SDK 有 `AudioPreferences`，界面没露）；`mediaAPI` 与带签名音频仍无语料。

## 十七、`chapterListURL`：章节列表在从作品页单跳到达的目录页（2026-09-14 立项，用户裁决「按设计实施」，同日实施）

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
- **引擎真跑逮到的形状（2026-09-14 第三次真跑）**：引擎与 App 都用 iPhone UA，sfacg 把 `book.sfacg.com/Novel/N/` 302 到移动站 `m.sfacg.com/b/N/`，
  目录 `/i/N/`、章节 `/c/N/`。规则因此是在移动站上学的：`chapterListURL` = `.book_Catalog > a:nth-of-type(2)`（相对**落点**解析，
  `document.finalURL` 是移动站地址）、`chapterRule.item` = `ul.mulu_list > a[href][href*='/c/']`、正文 `div.yuedu > div` + 段落 `p`。
  夹具切到 `sfacg-m-*`（引擎 UA `curl` 取得的移动站四页），`FixturePageContentLoader` 加 `redirects:` 模拟 302。
- **段落选择器相对容器**：Core `parseTextContent` 在容器元素上 `select(paragraph)`，容器之外的祖先不可见；引擎侧已把 `div.yuedu > div p` 这类
  抄了容器路径的答法归一为 `p`、重放改在脱离副本上 select（规则仓库设计书 6.1 更正 9）——这条差异是 Core 夹具测试先逮到的，App 侧不改语义。
- **模拟器逮到的传输层缺口（2026-09-14）**：sfacg 把 `https://book.sfacg.com/Novel/N/` 302 到 **`http://`** 的移动站、再 301 回 https；
  引擎的 HTTP 客户端无 ATS 跟得过去，App 的 URLSession 在 http 那一跳被 ATS 拒（详情页「网络请求失败 … App Transport Security」）。
  处置与有声书 mp3 同一纪律：`AlamofireHTTPClient` 加 `httpsUpgradingRedirector`（Alamofire `Redirector(.modify)`），跳转目标是 http 就升成 https
  （站点本就在 https 上服务），不开全局 ATS 例外；单元测试 `AlamofireHTTPClientRedirectTests`。
- **模拟器**：sfacg catalog 发布进公共目录后走通：添加 → 列表 → 作品 → 章节 → 正文（见规则仓库 HANDOFF 0.0.A25 续五）。

## 十八、站点书打开一章就把全书逐章取页 + 作品页封面被 ATS 拒（2026-09-14，sfacg 真机日志倒查，用户裁决「两处一起修」）

- **现象（真机日志）**：点开一章后，从该章起按阅读顺序连续取几十到上百个 `m.sfacg.com/c/…`（38380 上百章），同时成批创建 / 销毁 WebContent 进程；
  作品页头部封面报 `NSURLErrorDomain -1022`（`http://rs.sfacg.com/…NovelCover…`）。
- **成因一（Readium 预加载永不停止）**：`ReadiumSitePublicationBuilder` 手建的 `Publication` 没有 positions 服务，`positionsByReadingOrder()` 退到
  `positionsFromManifest` → 每章一个**空**数组；`EPUBNavigatorViewController` 用 `!positionsByReadingOrder.isEmpty` 判 `hasPositions`，外层非空即真；
  `PaginationView.scheduleLoadPages` 按「后 6 前 2 个 position」递减，每个 spread 贡献 0，永远凑不满，直到书头书尾——每章一个 WebView、一次取页。
  所有站点文字书都受影响（biquhua 同样）；本地 EPUB 走 Streamer 自带 positions，不受影响。
- **修法一**：文字书出版物带 `InMemoryPositionsService`，每章 1 个 position（`position = i + 1`、`totalProgression = i / 章数`）；预加载回到前 2 章、后 6 章。
  有声作品走 `AudioNavigator`，不加。固定输入：`BookSourceRuntimeEndToEndTests.biquhuaTextBookFlowsFromListToPublication` 断言 112 章各 1 个 position。
- **成因二（封面绕过共享图片通道）**：sfacg 桌面列表页封面是 `http://`；列表网格走共享 `CoverImageView`（http → https 候选、带 Referer）所以有图，
  `BookSiteDetailView` 头部与 `AudiobookPlayerView` 用系统 `AsyncImage` 直连，被 ATS 拒。
- **修法二**：两处改用 `CoverImageView`，不开全局 ATS 例外（与第十七节跳转升级、第十六节 mp3 同一纪律）。
- **模拟器实测（iPhone 16 Pro，本机家用出口）**：sfacg《大傩》（7 章）点开第七章 → 章节取页恰为 3 次（第五、六、七章），修前应为 7 次；正文正常显示；
  作品页封面出图、日志无 `-1022`。全量 506 / 89 过，架构边界干净。**真机待用户验。**

## 十九、站点书展示标题：列表标题与详情标题互相包含时取较短的（2026-09-15，用户裁决「互相包含取较短」）

- **现象**：sfacg 详情页与阅读器标题显示「大傩目录列表 - 小说频道 - SF轻小说」。
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
- **验证**：全量 507 / 89 过、架构边界干净；biquhua 端到端用例加断言（夹具真实列表条目标题带前缀、展示标题 = 「普罗之主」），套件 8 / 8 过。
  模拟器（iPhone 16 Pro，本机家用出口）：sfacg《在鱼塘钓鱼的两人》详情页导航栏 / 头部与阅读器标题都是干净书名（修前是「…目录列表 - 小说频道 - SF轻小说」）。
  biquhua 未在模拟器上看（来源位 1/1 被 sfacg 占用，换源要删来源并清历史），以夹具断言代替。**真机待用户验。**

## 二十、正文开头一段被丢 + 网页端没有正文的章节只显示标题（2026-09-15，sfacg 真机「只有标题没有内容」倒查，用户裁决「App Core 补取裸文本」「显示空章说明」）

- **现象一（开头丢段）**：sfacg 正文页 `div.yuedu > div` 里首句是第一个 `<p>` 之前的裸文本；规则 `segmentation: elements` + `paragraph: p`，
  Core 只取 `p`。已测 6 份正文页（run10 采集 4、语料 1、真机书 784586 一章）**6 份都丢开头**（「——2025年4月1日，魔女岛监狱宅邸——」「“求求你，救我……”」等）。
- **修法一（BrowseCraftCore，规则不动）**：段落规则是纯 CSS 选择器（无 functions / param / regex / replacement / fallback）时，
  经 `HTMLDocumentParsing.orderedTextBlocks` 按子节点文档顺序取块：直接子级非空裸文本、匹配选择器的元素各一块，
  含匹配元素的包裹层向下展开，其余元素（菜单、广告块）忽略。其他段落规则走原路径。biquhua 是 `lineBreaks`，不经过此路径。
  固定输入：Core `testSfacgChapterListURL…`（首段 = 「“求求你，救我，我真的已经……”」、无「上一章 / 下一章」）、`testElementsSegmentationKeepsBareTextInDocumentOrder`。
- **现象二（空章）**：《她靠马甲杀回，权贵圈争着喊夫人》（767172，签约作品）每章移动站页约 9.8KB、正文容器为空；
  桌面章节页 `#ChapterBody` 只有「全新的沉浸式互动小说…只能在APP上观看哦,扫码下载APP观看吧~」。不是付费、不是登录——**站点只在自家 App 内给正文**，任何规则都取不到。
  此前 Runtime 交出 0 段正文，阅读器只渲染章节标题，用户无从知道原因。
- **修法二**：Core 新增 `SourceRuntimeError.emptyContent(chapterURL:)`；Runtime `loadText` 拼页后 0 段即抛；
  `SiteBookChapterContainer` 接住它渲染说明页（章节标题 + `book_reader_chapter_no_web_content`：「这一章在网页上没有正文。站点可能只在自家 App 内提供这部作品的内容。」）。不认站点。
  固定输入：App `emptyChapterContentRendersANoticeInsteadOfATitleOnlyPage`。
- **验证**：Core 232 过（4 跳过）、Runtime 编译过、App 508 / 89 过、架构边界干净。模拟器未走（开屏「跳过」需人工）；**2026-09-15 真机通过（用户确认）**：
  784586 首章开头是「看见面前手的那瞬间……」；767172 章节显示说明页。
