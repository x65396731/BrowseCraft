# 本地书籍导入与 Readium 阅读器（设计，待拍板）

更新时间：2026-09-13
状态：**B0、B1、B2 已落地，入口已藏**（2026-09-13 ~ 09-14）。**用户 2026-09-14 裁决：App 不对用户暴露本地导入**——Library 工具栏的「书籍」入口与书架装配已去掉，B3（有声书播放器）不做；书架 / 阅读器 / 书签 / 三张表与仓储保留给站点抓取路（[读书 kind App 侧接线](Book-Kind-Wiring-Design.md) 批次 A ~ C）复用。B2 在模拟器上走通了导入 → 书架 → 阅读器 → 目录跳转 → 书签 → 退出重开续读（iPhone 16 Pro），**真机验收仍待用户**。B2 教训：书架与阅读器的两级目的地必须合成一个路由枚举在 Library 栈根声明一次（`LibraryBookRoute`）——书架用 `isPresented` 推入后在内部再声明第二级 `navigationDestination`，SwiftUI 报「declared earlier on the stack」并把推入弹回。B1 备注：嗅探器保留原文件扩展名（m4a / m4b 不改成 Readium 的规范名 mp4）；`ReadiumBookEnvironment.shared` 持有 HTTP 客户端、资产取回器、打开器与懒建的 `GCDHTTPServer`；夹具在 `BrowseCraftTests/Resources/Book/`（最小 EPUB、2 秒 mp3、带元数据 m4a）
影响范围：BrowseCraft 五层（Domain / Application / Infrastructure / Features / App）与 `scripts/check-architecture-boundaries.sh`；BrowseCraftCore、Domain 包、Runtime、APIKit **零改动**；漫画线与影视线代码零改动
前置：Readium 3.11.0 依赖已入库且首次整包 build 已通过（2026-09-13，0 error）；影视线与漫画线的真机复核仍待用户

## 一、结论

1. 首批只接两种本地文件：**EPUB** 与**音频书**（单个 `mp3 / m4a / m4b` 文件，或 `zip / zab` 音频包）。PDF 不接（读书规范 `BC-BOOK-012`：不为 PDF 生成规则；本地 PDF 可以以后单独立项），CBZ 不接（漫画线保持自研阅读器，AGENTS.md）。LCP 加密的 EPUB 不接，打开失败按错误提示。
2. 文件**复制进 App 容器**（`Application Support/Books/<uuid>.<ext>`），不用安全作用域书签引用外部文件——iCloud Drive 与「文件」App 里的文件会被移动、被按需卸载，引用会在第二次打开时失效。
3. `Locator` 在 Domain 里是**不透明 JSON 字符串**（Domain 与 Application 禁止依赖框架，Readium 的 `Locator` 只在 Infrastructure 与 Features 出现）；Readium 提供 `Locator.jsonString()` 与从 JSON 还原，续读位置、书签都存它，进度条用 `locations.totalProgression`。
4. 书架是 Library 里**独立于 Source 的一栏**：本地书不是 `Source`，不进 `SourceConfiguration`，不进 CloudKit 同步（首批）。等站点抓取路接上时，站点书与本地书共用同一个阅读器与同一张进度 / 书签表（外键从 `localBookID` 扩为「作品标识」，第 六节）。
5. 架构边界脚本要**先加一条**：`Domain` 与 `Application` 禁止 `import ReadiumShared / ReadiumStreamer / ReadiumNavigator / ReadiumAdapterGCDWebServer`（现在脚本的禁用清单里没有 Readium，靠自觉）。

## 二、已核对的事实（2026-09-13，只读）

### Readium 3.11.0（从 DerivedData 里的源码核对，不凭记忆）

| 能力 | API | 说明 |
|---|---|---|
| 打开文件 | `PublicationOpener(parser:contentProtections:)` + `open(asset:allowUserInteraction:credentials:…) async -> Result<Publication, PublicationOpenError>` | `parser` 用 `DefaultPublicationParser(httpClient:assetRetriever:pdfFactory:)`；`asset` 由 `AssetRetriever(formatSniffer:resourceFactory:archiveOpener:).retrieve(url:hints:)` 得到 |
| 音频书 | `AudioParser`：ZAB / 普通 ZIP 音频包，**也支持单个音频文件**；嗅探认 `mp3`、`m4a / m4b / mp4`、`aac / flac / ogg …` | 单个 `m4b` 就是一本书；章节由 `AVAudioPublicationManifestAugmentor` 从音频元数据补 |
| EPUB 阅读 | `EPUBNavigatorViewController(publication:initialLocation:readingOrder:config:httpServer:)`（`throws`；`publication.isRestricted` 时抛 `publicationRestricted`） | `httpServer` 用 `GCDHTTPServer`（`ReadiumAdapterGCDWebServer` 已链接） |
| 有声播放 | `AudioNavigator(publication:initialLocation:config:audioSession:)`：`play / pause / playPause / seek(to:) / seek(by:) / go(to:) / goForward / goBackward`、`playbackInfo`、`currentLocation` | **无 UI**，播放器界面自建；`audioSession` 缺省 `AudioSession.shared` |
| 位置 | `Navigator.currentLocation: Locator?`；`Locator` 是 `JSONObjectEncodable`（`jsonString()` / `jsonObject`），可从 JSON 还原 | 续读与书签都存 JSON |

### App 现状

- **没有任何文件导入入口**（全仓无 `fileImporter` / `UIDocumentPicker`）。
- 阅读历史按 kind 各一张表（`ComicChapterHistoryRecord` / `RSSReadingHistoryRecord` / `VideoWatchHistoryRecord`），Domain 用 `ReadingHistoryEntry.Kind`（`rss / comic / video / temporary`）聚合；漫画的续读位置存 `lastReaderPageURL`。
- 数据库只经 `AppDatabaseMigrations` 追加 `vN.描述` 迁移演进，`AppDatabaseSchemaSnapshotTests` 比对 `sqlite_master` 快照——**加表必须同时更新快照**。数据库文件在 `Application Support`。
- 分层不变量由 `scripts/check-architecture-boundaries.sh` 在预构建阶段强制：Domain / Application 禁框架 import，`BrowseCraftAPIKit` 只许 Infrastructure 与 `AppContainer`，跨层类型引用按层名扫描。
- 阅读器入口：`Features/Library/Comic/Reader/ReaderView`，由 `LibraryView`、`ComicDetailView`、`HistoryView` 三处打开；视频播放在 `Features/Library/Video/Player/`。
- Library 的分流轴是 `Source.configuration.kind`（`SourceRuntimeKind`），本地书不在这条轴上。

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

- `ReadiumBookPublicationOpener`：持有一个 `AssetRetriever`、`DefaultPublicationParser`、`PublicationOpener` 与一个进程级 `GCDHTTPServer`（EPUB Navigator 需要）；`open` 走 `allowUserInteraction: false`。
- `ReadiumBookFileInspector`：用 Readium 的格式嗅探（`FormatSniffer` + 文件扩展名 / 媒体类型提示）。
- `FileSystemBookFileStore`：`Application Support/Books/`，文件名用 `LocalBook.id`。
- GRDB：`local_books`、`book_reading_progress`、`book_bookmarks` 三张表，一条迁移 `v3.local-books`（在 `sourcesAddOriginIdentifier` 之后追加），`AppDatabaseSchemaSnapshotTests` 快照同步更新；Record 只做行映射。
- 不进 CloudKit（首批）：文件本身不同步，进度与书签也先不同步，避免「云端有进度、本机无文件」的半状态。

### 3.4 Features

- `Features/Library/Book/`：`BookShelfView`（从 Library 工具栏的「Books」进入；`fileImporter` 允许的 `UTType`：`epub`、`mp3`、`mpeg4Audio`（`m4a / m4b`）、`zip`，多选）、`BookShelfViewModel`、`LibraryBookRoute`（书架 / 某本书两级路由，只在 `LibraryView` 栈根声明）。
- `Features/Library/Book/Reader/BookReaderView`：`UIViewControllerRepresentable` 承载 `EPUBNavigatorViewController`；`navigator(_:locationDidChange:)` 节流（1 秒）后调保存用例，退出时再保存一次；工具栏：目录、书签、字号 / 主题（`EPUBPreferences`）。
- `Features/Library/Book/Player/AudiobookPlayerView`：自建 UI 包 `AudioNavigator`——播放 / 暂停、进度条（`playbackInfo`）、±15 秒、章节列表（`readingOrder`）、倍速（`AudioPreferences`）；后台播放要在 `project.yml` 加 `UIBackgroundModes: audio`，并接 `MPRemoteCommandCenter` / Now Playing（Infrastructure 适配，AVFoundation 只许在 Infrastructure / Features）。
- 书签：两种阅读器共用 `BookBookmarksSheet`，点选即 `go(to:)`。
- `App/Composition/FeatureComposition` 加 `makeBookShelf`，`SourceRuntimeComposition` 不动。

### 3.5 边界脚本

`scripts/check-architecture-boundaries.sh` 的 Domain / Application 禁用清单加 `ReadiumShared|ReadiumStreamer|ReadiumNavigator|ReadiumAdapterGCDWebServer|MediaPlayer`；`docs/architecture.md` §3 同步一句。

## 四、分批（每批单独拍板、提交、推送）

| 批 | 内容 | 验收 |
|---|---|---|
| B0 | 边界脚本 + Domain 模型与仓储协议 + Application 端口与用例（用测试替身）+ 迁移 `v3.local-books` + 快照更新 | `BrowseCraftTests` 全过；快照测试过；build 过 |
| B1 | Infrastructure：Readium 打开器 / 嗅探器 / 文件存储 / GRDB 仓储；用固定输入（一本无 DRM 的小 EPUB、一个 10 秒 mp3、一个两文件 zip）测「导入 → 落库 → 打开 → 元数据正确」 | 单元测试过；导入失败回滚文件的用例过 |
| B2 | 书架 + EPUB 阅读器 + 续读进度 + 书签 | **用户真机**：导入 EPUB、读几页、退出再进回到原位、书签跳转 |
| B3 | 有声书播放器 UI + 后台播放 + 锁屏控制 + 章节 / 倍速 | **用户真机**：导入 m4b，锁屏继续播，退出再进回到原位 |

B2 之后再回到 [读书 kind App 侧接线](Book-Kind-Wiring-Design.md) 的批次 A（站点抓取路），届时 RWPM 装配的产物就是同一个 `BookPublicationHandle`。

## 五、验证命令

```bash
scripts/check-architecture-boundaries.sh
scripts/regenerate-project.sh && xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft -destination 'platform=iOS Simulator,id=135E66FA-674C-4FE7-8813-3099C857420E' build
xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft -destination 'platform=iOS Simulator,id=135E66FA-674C-4FE7-8813-3099C857420E' test -only-testing:BrowseCraftTests
```

## 六、待裁决

1. **History 页是否纳入本地书**：**用户裁决 B2 不纳入**，站点路接上时一起做（`ReadingHistoryEntry.Kind` 加 `.book` 会牵动 `HistoryView` / `HistoryEntryRowView` 等既有分流点）。
2. **进度与书签是否上 CloudKit**：**用户裁决首批不上**（第 3.3 节的理由）。
3. **站点书与本地书的作品标识**：站点书没有 `LocalBook`，进度表的外键要从 `bookID: UUID` 扩为「本地 UUID 或 `sourceID + itemID`」——建议在批次 A 时改，本文先按本地 UUID。
4. **PDF**：本地 PDF 用 `PDFNavigatorViewController` 成本很低，但读书规范把 PDF 排除在站点路之外；是否作为本地专属格式接，由用户定。

## 七、风险

- `GCDHTTPServer` 监听本机端口，与 App 既有的 Alamofire / WebKit 层无冲突，但要确认 App Transport Security 对 `http://127.0.0.1` 的例外（Readium 自带处理，build 后核）。
- 后台音频需要新的 capability（`UIBackgroundModes`），必须写在 `project.yml`（`pbxproj` 是生成的，Xcode 里改会被下次 regenerate 冲掉）。
- iCloud Drive 里未下载的文件：`fileImporter` 给的 URL 可能是占位，复制前要 `startDownloadingUbiquitousItem` 或提示用户。
- 大文件（数百 MB 的 m4b）：复制与 SHA-256 要在后台任务里做，书架显示「导入中」。

## 八、入口已藏（用户 2026-09-14 裁决）

用户在 B2 落地后问「为什么有本地存储的功能，这个功能和漫画有什么关系」：本地导入来自交接单第五节的建议顺序，与漫画无关，也不涉及规则生成，
对主线（通用网站规则生成 → App 消费 book catalog）只是垫脚石。裁决：**保留代码、去掉入口**。

- 去掉：`LibraryView` 工具栏的「Books」`NavigationLink`；`RootView` 不再创建 `BookShelfViewModel` 与阅读器工厂闭包（`LibraryView` 的两个可选参数缺省为 nil）。
- 保留：`BookShelfView` / `BookShelfViewModel`（含 `fileImporter`，不可达）、`BookReaderView` / `BookReaderViewModel` / `EPUBNavigatorRepresentable`、`LibraryBookRoute` 与 `LibraryView.bookDestination`、
  Domain / Application / Infrastructure 的全部本地书模型、用例、适配器、三张表与仓储、`BookFeatureFactory`。站点抓取路接线时，`.book` 路由与阅读器直接复用；
  `LocalBook` 届时按第六节第 3 条扩为「本地 UUID 或 sourceID + itemID」的作品标识。
- 不做：B3 有声书播放器；本地 PDF。
- 迁移 `v3.local-books` 已入库存，不回退（表空着不影响任何功能；回退迁移会改动已发布设备的账本）。
