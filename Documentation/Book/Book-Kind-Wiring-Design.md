# 读书 kind（book）App 侧接线（立项，待拍板）

更新时间：2026-09-13
状态：**立项，未实施**——顺序与发布策略已由用户裁决（第四、五节）；每一批实施各自另拍板
影响范围：BrowseCraftAPIKit、BrowseCraftDomain、BrowseCraftCore、BrowseCraftRuntime、BrowseCraft 五个仓库；影视线与漫画线代码零改动
前置：服务器接线已部署（PortalCore `b9fc2ff`，2026-09-13 深夜），`POST /v1/rule-generations` 已接受 `sourceKind: book`；Readium 3.11.0 依赖已入库（BrowseCraft `7ad27044`），**整包尚未 build 过**

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

Core 预期 218 条通过、4 条跳过（交接单第四节）；整包 build 结果目前**未知**，是批次 B 的第一件事。

## 七、与其它文档的关系

- 规则合同：规则仓库 `docs/rules/book-catalog-profile.md`（App 消费的接口定稿）、`docs/rules/book-generation-design.md` `BC-BOOK-048`（本文即其 App 部分的立项）。
- 服务器接线：PortalCore `docs/architecture/rule-generation-migration-plan.md` §14。
- Readium 依赖与 SwiftSoup fork：本目录 `Readium-Integration-Handoff.md`。
