# 本地书籍导入与 Readium 阅读器

影响范围：BrowseCraft 五层（Domain / Application / Infrastructure / Features / App）与 `scripts/check-architecture-boundaries.sh`；BrowseCraftCore、Domain 包、Runtime、APIKit **零改动**；漫画线与影视线代码零改动。书架 / 阅读器 / 书签 / 三张表与仓储保留给站点抓取路（[读书 kind App 侧接线](Book-Kind-Wiring-Design.md) 批次 A ~ C）复用；B3（本地有声书播放器）按裁决不做，站点有声作品的播放器见 [读书 kind App 侧接线](Book-Kind-Wiring-Design.md) 第十六节。

- `BCA-UI-001` 书架与阅读器的两级目的地必须合成一个路由枚举在 Library 栈根声明一次（`LibraryBookRoute`）——书架用 `isPresented` 推入后在内部再声明第二级 `navigationDestination`，SwiftUI 报「declared earlier on the stack」并把推入弹回。

- B1 备注：嗅探器保留原文件扩展名（m4a / m4b 不改成 Readium 的规范名 mp4）；`ReadiumBookEnvironment.shared` 持有 HTTP 客户端、资产取回器与打开器（不再持有本地 HTTP 服务）；夹具在 `BrowseCraftTests/Resources/Book/`（最小 EPUB、2 秒 mp3、带元数据 m4a）。

> 实施与验证状态见 [STATUS.md](../STATUS.md)；分批落地与裁决的叙事事实见 [status-log.md](../history/status-log.md)。

## 一、结论

1. 首批只接两种本地文件：**EPUB** 与**音频书**（单个 `mp3 / m4a / m4b` 文件，或 `zip / zab` 音频包）。PDF 不接（读书规范 `BC-BOOK-012`：不为 PDF 生成规则；本地 PDF 可以以后单独立项），CBZ 不接（漫画线保持自研阅读器，AGENTS.md）。LCP 加密的 EPUB 不接，打开失败按错误提示。
2. `BCA-BOOK-002` 文件**复制进 App 容器**（`Application Support/BrowseCraft/Books/<uuid>.<ext>`，与 AppDatabase 同一个 `BrowseCraft` 目录），不用安全作用域书签引用外部文件——iCloud Drive 与「文件」App 里的文件会被移动、被按需卸载，引用会在第二次打开时失效。
3. `BCA-BOOK-003` `Locator` 在 Domain 里是**不透明 JSON 字符串**（Domain 与 Application 禁止依赖框架，Readium 的 `Locator` 只在 Infrastructure 与 Features 出现）；Readium 提供 `Locator.jsonString()` 与从 JSON 还原，续读位置、书签都存它，进度条用 `locations.totalProgression`。
4. 书架是 Library 里**独立于 Source 的一栏**：本地书不是 `Source`，不进 `SourceConfiguration`，不进 CloudKit 同步（首批）。等站点抓取路接上时，站点书与本地书共用同一个阅读器与同一张进度 / 书签表（外键从 `localBookID` 扩为「作品标识」，第 六节）。
5. Readium 模块进不了 `Domain` 与 `Application`，由架构边界脚本执行：`BCA-ARCH-002`。

## 二、Readium 3.11.0 的能力（从源码核对，不凭记忆）

| 能力 | API | 说明 |
|---|---|---|
| 打开文件 | `PublicationOpener(parser:contentProtections:)` + `open(asset:allowUserInteraction:credentials:…) async -> Result<Publication, PublicationOpenError>` | `parser` 用 `DefaultPublicationParser(httpClient:assetRetriever:pdfFactory:)`；`asset` 由 `AssetRetriever(formatSniffer:resourceFactory:archiveOpener:).retrieve(url:hints:)` 得到 |
| 音频书 | `AudioParser`：ZAB / 普通 ZIP 音频包，**也支持单个音频文件**；嗅探认 `mp3`、`m4a / m4b / mp4`、`aac / flac / ogg …` | 单个 `m4b` 就是一本书；章节由 `AVAudioPublicationManifestAugmentor` 从音频元数据补 |
| EPUB 阅读 | `EPUBNavigatorViewController(publication:initialLocation:readingOrder:config:httpServer:)`（`throws`；`publication.isRestricted` 时抛 `publicationRestricted`） | 用不带 `httpServer` 的初始化；App 不链接 `ReadiumAdapterGCDWebServer` |
| 有声播放 | `AudioNavigator(publication:initialLocation:config:audioSession:)`：`play / pause / playPause / seek(to:) / seek(by:) / go(to:) / goForward / goBackward`、`playbackInfo`、`currentLocation` | **无 UI**，播放器界面自建；`audioSession` 缺省 `AudioSession.shared` |
| 位置 | `Navigator.currentLocation: Locator?`；`Locator` 是 `JSONObjectEncodable`（`jsonString()` / `jsonObject`），可从 JSON 还原 | 续读与书签都存 JSON |

## 三、设计

### 3.1 Domain（纯值，无框架）

```
LocalBook            id: UUID, userID: String, title: String, author: String?, format: LocalBookFormat (epub | audiobook),
                     fileRelativePath: String, coverRelativePath: String?, fileSHA256: String, byteCount: Int,
                     importedAt: Date, lastOpenedAt: Date?, deletedAt: Date?
BookReadingProgress  bookID: UUID, userID: String, locatorJSON: String, totalProgression: Double?, updatedAt: Date
BookBookmark         id: UUID, bookID: UUID, userID: String, locatorJSON: String, title: String?, snippet: String?, createdAt: Date
```

仓储协议：`LocalBookRepository`、`BookReadingProgressRepository`、`BookBookmarkRepository`（放在 App 目标的 `Domain/`，与既有 10 个仓储协议同处；不进 `BrowseCraftDomain` 包——那个包是 Source 与 Catalog 的合同，本地书与之无关）。

### 3.2 Application（用例与端口）

| 端口（Application 定义，Infrastructure 实现） | 作用 |
|---|---|
| `BookFileInspecting` | 对一个文件 URL 嗅探格式（epub / audiobook / 不支持），不打开出版物 |
| `BookPublicationOpening` | 打开容器内文件，返回不透明的 `BookPublicationHandle`（Infrastructure 里包着 Readium `Publication`），并给出标题 / 作者 / 封面数据 / 是否受限 |
| `BookFileStoring` | 把安全作用域 URL 的文件复制进 `Books/`，返回相对路径、SHA-256 与字节数；删除时同时删文件 |

用例：`ImportLocalBookUseCase`（嗅探 → 复制 → 打开一次取元数据与封面 → 落库；任一步失败回滚文件）、`ListLocalBooksUseCase`、`OpenLocalBookUseCase`（取 handle + 上次进度）、`SaveBookReadingProgressUseCase`（节流由 Features 做，用例只写）、`DeleteLocalBookUseCase`、`AddBookBookmarkUseCase / ListBookBookmarksUseCase / RemoveBookBookmarkUseCase`。

### 3.3 Infrastructure

- `ReadiumBookPublicationOpener`：持有一个 `AssetRetriever`、`DefaultPublicationParser`、`PublicationOpener`，EPUB Navigator 不需要本地 HTTP 服务；`open` 走 `allowUserInteraction: false`。
- `ReadiumBookFileInspector`：用 Readium 的格式嗅探（`FormatSniffer` + 文件扩展名 / 媒体类型提示）。
- `FileSystemBookFileStore`：`Application Support/BrowseCraft/Books/`（`BCA-BOOK-002`），文件名用 `LocalBook.id`。
- GRDB：`local_books`、`book_reading_progress`、`book_bookmarks` 三张表，一条迁移 `v3.local-books`（在 `sourcesAddOriginIdentifier` 之后追加），`AppDatabaseSchemaSnapshotTests` 快照同步更新；Record 只做行映射。
- 不进 CloudKit（首批）：文件本身不同步，进度与书签也先不同步，避免「云端有进度、本机无文件」的半状态。

### 3.4 Features

- `Features/Library/Book/`：`BookShelfView`（入口已藏，见第八节；`fileImporter` 允许的 `UTType`：`epub`、`mp3`、`mpeg4Audio`（`m4a / m4b`）、`zip`，多选）、`BookShelfViewModel`、`LibraryBookRoute`（书架 / 某本书两级路由，只在 `LibraryView` 栈根声明）。
- `Features/Library/Book/Reader/BookReaderView`：`UIViewControllerRepresentable` 承载 `EPUBNavigatorViewController`；`navigator(_:locationDidChange:)` 节流（1 秒）后调保存用例，退出时再保存一次；工具栏：目录、书签、字号 / 主题（`EPUBPreferences`）。
- `Features/Library/Book/Reader/AudiobookPlayerView`：自建 UI 包 `AudioNavigator`，控件、锁屏与后台播放的做法见读书接线合同第十六节（`AudiobookRemoteControls`、手写 `Info.plist` 的 `UIBackgroundModes: audio`）；本地导入的音频书不路由到它（入口已藏）。
- 书签：两种阅读器共用同一张书签表与同一组用例（`BookBookmark`、`AddBookBookmarkUseCase` /
  `ListBookBookmarksUseCase` / `RemoveBookBookmarkUseCase`），点选即 `go(to:)`；
  呈现层内联在 `BookReaderView` 的 `.sheet` 里，没有独立的 sheet 类型。
- `App/Composition/FeatureComposition` 加 `makeBookShelf`，`SourceRuntimeComposition` 不动。

### 3.5 边界脚本

`scripts/check-architecture-boundaries.sh` 的 Domain / Application 禁用清单加 `ReadiumShared|ReadiumStreamer|ReadiumNavigator|ReadiumAdapterGCDWebServer|MediaPlayer`；`docs/architecture.md` §3 同步一句。

## 四、分批

B0、B1、B2 已落地，B3 按裁决不做，状态见 [STATUS.md](../STATUS.md) 第 1 节；当年的分批表与验收口径见 [status-log.md](../history/status-log.md)。

## 五、验证命令

```bash
scripts/check-architecture-boundaries.sh
scripts/regenerate-project.sh && xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' build
xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' test -only-testing:BrowseCraftTests
```

## 六、裁决与现状

1. **History 页**：本地书不进 History（入口已藏）；站点书已进 History，接线见 [读书 kind App 侧接线](Book-Kind-Wiring-Design.md) 第二十三节。
2. **进度与书签上 CloudKit**：本地书的进度与书签不上云（第 3.3 节的理由）；站点书的续读位置随 `HistoryEntry` 同步，见 [续看位置同步](History-Resume-Sync-Design.md)。
3. **作品标识**：进度表与书签表的外键已由迁移 `v4.book-progress-detached-from-local-books` 从本地 UUID 扩为作品标识（`SiteBookIdentity`），站点书与本地书共用同一张表。
4. **PDF**（仍待裁决）：本地 PDF 用 `PDFNavigatorViewController` 成本很低，但读书规范把 PDF 排除在站点路之外；是否作为本地专属格式接，由用户定。

## 七、风险

- 本地 HTTP 服务的端口与 App Transport Security 例外问题已不存在：EPUB Navigator 用不带 `httpServer` 的初始化，App 不监听本机端口。
- 后台音频需要 `UIBackgroundModes: audio`，按 `BCA-BUILD-004` 写在被跟踪的手写 `BrowseCraft/Info.plist`（`project.yml` 以 `INFOPLIST_FILE` 指向它），不在 Xcode 编辑器里勾。
- iCloud Drive 里未下载的文件：`fileImporter` 给的 URL 可能是占位，复制前要 `startDownloadingUbiquitousItem` 或提示用户。
- 大文件（数百 MB 的 m4b）：复制与 SHA-256 要在后台任务里做，书架显示「导入中」。

## 八、入口已藏

- 去掉：`LibraryView` 工具栏的「Books」`NavigationLink`；`RootView` 不再创建 `BookShelfViewModel` 与阅读器工厂闭包（`LibraryView` 的两个可选参数缺省为 nil）。
- 保留：`BookShelfView` / `BookShelfViewModel`（含 `fileImporter`，不可达）、`BookReaderView` / `BookReaderViewModel` / `EPUBNavigatorRepresentable`、`LibraryBookRoute` 与 `LibraryView.bookDestination`、
  Domain / Application / Infrastructure 的全部本地书模型、用例、适配器、三张表与仓储、`BookFeatureFactory`。站点抓取路接线时，`.book` 路由与阅读器直接复用；
  作品标识已按第六节第 3 条扩为「本地 UUID 或 sourceID + itemID」。
- 不做：B3 有声书播放器；本地 PDF。
- 迁移 `v3.local-books` 已入库存，不回退（表空着不影响任何功能；回退迁移会改动已发布设备的账本）。
