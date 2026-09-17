# BrowseCraft 代码审计报告（2026-09-18）

日期：2026-09-18
范围：BrowseCraft App 工程 + BrowseCraftCore / BrowseCraftDomain / BrowseCraftRuntime / BrowseCraftAPIKit 四个包
方式：只读审计。未改代码、未 build、未跑测试。警告清单取自 Xcode 最近一次构建日志（2026-09-16 22:40「Build TEST BrowseCraft」），该日志与当前 HEAD（f263274b）之间没有新提交，因此清单与当前代码一致。

## 1. 总览

| 项 | 结论 |
|---|---|
| 警告 | 39 条 = 37 条编译器警告 + 1 条广告配置脚本提示 + 1 条 AppIntents 元数据提示。全部定位到文件与行。 |
| 架构 | 依赖方向无违规；App 层与包之间无同名类型重复。短板：包侧未开严格并发、Domain/Runtime 无测试目标、Core 可拆、边界脚本有绕过口。 |
| 性能 | GRDB、索引、列表懒加载、并发、Release 优化均正常。热点集中在 WebView 稳定判定、图片解码尺寸、正则重复编译、列表加载冗余读写。 |

代码规模：

| 模块 | Swift 文件 | 行数 |
|---|---|---|
| App（BrowseCraft/） | 367 | 49,711 |
| BrowseCraftCore | 68 | 28,330 |
| BrowseCraftRuntime | 46 | 13,359 |
| BrowseCraftDomain | 38 | 2,203 |
| BrowseCraftAPIKit | 14 | 1,645 |

## 2. 警告清单（39 条）

### 2.1 共同根因

四个包的 `Package.swift` 都没有 `swiftSettings`，包内以 Swift 5 最低并发检查编译；App 在 `project.yml` 开了 `SWIFT_STRICT_CONCURRENCY: complete`。包内类型的 Sendable 缺口因此全部在 App 调用点爆出，而不是在类型声明处。修正的第一步是给四个包加同样的严格并发闸门，把当前状态固化成基线。

### 2.2 按组明细

**A. Readium 非 Sendable 类型跨隔离域（18 条）**

| 文件:行 | 警告 |
|---|---|
| Features/Library/Book/Reader/AudiobookPlayerView.swift:37,45,46,51,53 | sending 'navigator' risks causing data races |
| Features/Library/Book/Reader/AudiobookRemoteControls.swift:28,29,31,33,38 | sending 'navigator' risks causing data races |
| Features/Library/Book/Reader/BookReaderViewModel.swift:107 | sending 'publication' risks causing data races |
| Features/Library/Book/Reader/BookReaderViewModel.swift:387,394 | sending value of non-Sendable type 'any Navigator' |
| Features/Library/Book/Reader/EPUBNavigatorRepresentable.swift:21 | init(publication:initialLocation:readingOrder:config:httpServer:) is deprecated |
| Infrastructure/Book/ReadiumBookEnvironment.swift:16（2 条） | 'GCDHTTPServer' is deprecated |
| Infrastructure/Book/ReadiumBookEnvironment.swift:33 | static property 'audioSpecifications' is not concurrency-safe（Set<FormatSpecification> 非 Sendable） |
| Infrastructure/Book/ReadiumBookEnvironment.swift:3 | add '@preconcurrency' to suppress warnings from module 'ReadiumShared' |

根因：Readium 3.11 的 `Navigator` 协议与 `AudioNavigator` 类既不是 `@MainActor` 也不是 `Sendable`，其 async 方法是 nonisolated；`FormatSpecification` 同样非 Sendable。GCDHTTPServer 在 3.x 已不再需要，`EPUBNavigatorViewController` 提供了不带 `httpServer` 的 init（swift-toolkit `Sources/Navigator/EPUB/EPUBNavigatorViewController.swift:278`）。

**B. 推送代理闭包捕获（8 条）**

| 文件:行 | 警告 |
|---|---|
| BrowseCraftApp.swift:143,157 | sending 'userInfo' risks causing data races；capture of 'userInfo' with non-Sendable type '[AnyHashable: Any]' |
| BrowseCraftApp.swift:144,158 | sending 'completionHandler' risks causing data races；capture of 'completionHandler' with non-Sendable type |

根因：`UNUserNotificationCenterDelegate` 在 SDK 头文件里既没有 `NS_SWIFT_UI_ACTOR` 也没有 `NS_SWIFT_SENDABLE`，两个方法标了 `nonisolated`，再用 `DispatchQueue.main.async`（@Sendable 闭包）捕获非 Sendable 参数。

**C. Runtime 协议未声明 Sendable（3 条）**

| 文件:行 | 警告 |
|---|---|
| Application/UseCases/Book/LoadBookPublicationUseCase.swift:102 | capture of 'contentRuntime' with non-Sendable type 'any SourceBookContentRuntime' in a '@Sendable' closure |
| Application/UseCases/Book/LoadBookPublicationUseCase.swift:1 | add '@preconcurrency' to suppress warnings from module 'BrowseCraftCore' |
| Application/UseCases/Book/LoadBookPublicationUseCase.swift:31 | converting non-Sendable function value to '@Sendable () -> Date' |

根因：Core 的 `SourceRuntime` 协议（`Runtime/SourceRuntimeContract.swift:5`）没有继承 `Sendable`，而三个实现 `VideoSourceRuntime`、`ComicSourceRuntime`、`BookSourceRuntime` 都已是 `Sendable` struct。第 31 行是 `Date.init` 函数引用不被推断为 @Sendable。

**D. 缺 import（4 条）**

| 文件:行 | 警告 |
|---|---|
| Shared/UI/CoverImageView.swift:10,11 | cannot use protocol 'BrowserRequestHeaderProviding' / 'SystemCookieHeaderProviding'；'BrowseCraftDomain' was not imported |
| Shared/UI/ItemThumbnailImageView.swift:8,9 | 同上 |

**E. 静态 formatter（2 条）**

| 文件:行 | 警告 |
|---|---|
| Infrastructure/Generation/APIKitVideoGenerationOutcomesClient.swift:39,44 | static property 'isoParser' / 'isoParserWithoutFraction' is not concurrency-safe（ISO8601DateFormatter 非 Sendable） |

**F. 已废弃 API（2 条）**

| 文件:行 | 警告 |
|---|---|
| Infrastructure/Preflight/PreflightRenderedPageLoader.swift:58（2 条） | 'processPool' / 'WKProcessPool' was deprecated in iOS 15.0 |

**G. 非编译器（2 条）**

| 来源 | 内容 | 处理 |
|---|---|---|
| scripts/check-ad-configuration.sh:26 | Rewarded ad unit is Google's sample unit for environment TEST | 设计如此，PROD 归档前替换广告单元即消失，不需要改代码 |
| appintentsmetadataprocessor | Metadata extraction skipped, no AppIntents.framework dependency found | Xcode 工具噪音，无害 |

## 3. 多包架构

### 3.1 依赖方向（合规）

App 各层对包的 import 次数：

| 层（文件数） | Core | Domain | Runtime | APIKit |
|---|---|---|---|---|
| App (16) | 2 | 10 | 4 | 2 |
| Application (101) | 26 | 36 | 13 | 0 |
| Domain (43) | 9 | 13 | 0 | 0 |
| Features (95) | 17 + 4 @preconcurrency | 43 | 7 | 0 |
| Infrastructure (93) | 10 | 19 | 1 | 5 |
| Shared (17) | 3 | 6 | 0 | 0 |

- APIKit 只出现在 Infrastructure/{Identity,Push,Generation} 与 App/Composition，符合脚本白名单。
- SwiftSoup 只在 Core 的 3 个白名单文件；App 与 Domain/Runtime 包零 import。
- App 内 Domain（72 个类型）、Application（271）与 BrowseCraftDomain 包（76）之间没有同名类型。分工是：包 Domain 持有 `Source`、`SourceConfiguration`、各 port 协议；App Domain 持有持久化实体与 13 个 Repository 协议。
- `print(`、`fatalError`、`as!` 全部模块为 0；`try!` 仅 Runtime 2 处（`Book/BookSourceRuntime.swift:322,369`，字面量正则，安全）。

### 3.2 问题

1. **包侧未开严格并发。** 见 2.1。
2. **BrowseCraftDomain 与 BrowseCraftRuntime 没有 `Tests/` 目录与 testTarget。** 它们的测试都在 App 的 BrowseCraftTests（分别 import 57 次与 28 次），改 Runtime 必须整机 build 才能验证，`swift test` 不可用。
3. **Core 是单 target 混合了规则模型、校验、发现与解析执行。** 测量：Domain 包用到 Core 的 31 个符号全部来自 `Rule/`（21）、`Source/`（7）、`Runtime/`（3），零个来自 `Parsing/`；App 的 Domain/Features/Shared 层同样零个；只有 Runtime 包（28 个符号、5 个文件）真正构造解析器。拆成「规则模型」（Foundation-only）与「解析」（依赖 SwiftSoup）两个 target 后，Domain 与大半 App 不再传递链接 SwiftSoup，改解析器不触发全量重编。前置：`Parsing/Extraction/DefaultRuleExtractionEngine.swift:10` 默认构造 `SwiftSoupHTMLDocumentParser()` 这一处要先改成注入。Core 最大文件：`Rule/SiteRuleModels.swift` 3,243 行、`Rule/VideoSiteRuleValidationOperations.swift` 2,894 行、`Rule/ComicSiteRuleV2ValidationOperations.swift` 2,430 行、`Parsing/Discovery/DefaultSourceDiscoveryAnalyzer.swift` 2,072 行。
4. **边界脚本有绕过口。** `check-architecture-boundaries.sh:60` 只匹配 `^import X$`，`@preconcurrency import` 与 `import struct X.Y` 都能穿过；Features 已有 4 处 `@preconcurrency import BrowseCraftCore`（LibraryViewModel.swift:4、VideoDetailViewModel.swift:3、VideoPlayerViewModel.swift:3、SourcesViewModel.swift:4），Infrastructure 有 20 处 `@preconcurrency import GRDB/Nuke`。脚本也不检查 Features→Infrastructure 方向，实际已有 11 处直接引用（如 `Features/Settings/SettingsViewModel.swift:41` 引用 `ImageCacheConfigurator`、Features 直接引用 `ReadiumBookEnvironment`）；Shared→Application 2 处（`Shared/Errors/RuleExecutionError.swift:19,27`）、Shared→Infrastructure 2 处（`Shared/UI/ItemThumbnailImageView.swift:55,119`）。`declared_types` 正则不识别 `@Observable`、嵌套类型。`print(` 检查只覆盖 App 根目录。
5. **`App/Compatibility/CoreRuleCandidateNaming.swift`** 的 13 个 typealias 只剩 2 个外部使用者，可退役。
6. App 超过 800 行的文件 4 个：`Application/Diagnostics/VideoRuntimeAudit/VideoRuntimeAuditService.swift` 1,265、`Features/Sources/SourcesViewModel.swift` 1,156、`Features/Library/LibraryViewModel.swift` 1,133、`Features/Library/Video/Player/VideoWebPlayerCoordinator.swift` 801。Runtime：`Video/Loading/VideoSourcePlaybackLoader.swift` 1,396。

## 4. 性能

### 4.1 检查过且正常

- GRDB：`DatabasePool`（WAL）、6.29.3；索引覆盖 `sources(userID, deletedAt, updatedAt DESC)`、`video_watch_history(userID, updatedAt)`、`(userID, sourceID, detailURL)`、favorite/history 各用户与时间索引；仓库层无 N+1；无 `ValueObservation` 误用。
- 列表：长列表均为 `LazyVGrid`/`LazyVStack`/`List`，分页由单个哨兵 `onAppear` 触发；`AnyView` 0 处；`LibraryViewModel` 为 `@Observable`。
- 并发：无 `DispatchSemaphore`、`Task.detached`、线程 sleep；10 处 `DispatchQueue.main.async` 全是 AVPlayer/KVO/通知桥接；无全局 actor 串行化解析。
- Runtime：检测词典 `static let` 只加载一次；运行时工厂在 `SourceRuntimeComposition` 组装一次；`ResourcePipelinePlanCache` actor 已接入。
- 启动：数据库迁移与 Keychain 引导在 `AppBootstrapLoader` actor 内，不在主线程。
- 构建：Release `-O` + WMO，Debug `-Onone`；字符串表 24-28 KB。

### 4.2 热点（按用户可感知影响排序）

| # | 级别 | 位置 | 成本 | 通用修法 |
|---|---|---|---|---|
| P1 | 高 | `Infrastructure/Network/WKWebViewHTMLLoader.swift:67,71,107,139,438,452` | didFinish 后固定睡 500 ms，再至少 6 轮 × 300 ms 求 `outerHTML.length`，每轮序列化整棵 DOM；所有 `needsWebView` 规则至少多付 2.3 s；每次请求新建 WKWebView | 稳定判定改为注入 `MutationObserver` 的静默窗口，窗口时长按请求显式声明，当前取值作为基线；loader 内复用 WKWebView |
| P2 | 高 | `Features/Library/Comic/Reader/ReaderPageImageView.swift:120`、`Components/ReaderImageProcessing.swift:16,37` | 挂的是 Nuke processor，全尺寸位图先分配再重绘；已有基于 CGImageSource 缩略解码的 `ReaderImageDecoder` 只在保护资源路径（`ReaderViewModel.swift:416`）用，未注册进 Nuke | 通过 `ImagePipeline.Configuration.makeImageDecoder` 注册 `ReaderImageDecoder`，按请求 `userInfo` 里的目标宽度解码，移除 processor；任何 kind 的降采样解码走同一条路 |
| P3 | 高 | `Shared/UI/CoverImageView.swift:42`、`Shared/UI/ItemThumbnailImageView.swift:34`、`ItemThumbnailImageCachePlugin.swift:21-23` | 不带 resize processor，缩略图缓存上限 64 MB 实际只装约十张全尺寸封面，滚动反复解码；全项目无 `ImagePrefetcher` | 按单元格尺寸加 `.resize(size:unit:.points)`；`LazyVGrid` 出现/消失驱动 `ImagePrefetcher`；漫画阅读器同法加预取 |
| P4 | 中 | `BrowseCraftCore/.../Parsing/Extraction/DefaultRuleExtractionEngine.swift:322` 及 Core/Runtime 共 14 个文件 | 调用点 `NSRegularExpression(pattern:)`，无任何缓存；40 条目 × 4 正则字段 = 160 次编译/页 | Core 内一个按 pattern+options 键控、加锁、有界的正则缓存，所有 kind 共用 |
| P5 | 中 | `Application/UseCases/Library/LibraryPersistenceCoordinator.swift:44-46`、`Infrastructure/Database/Repositories/GRDBSourceRepository.swift:110` | 每次进列表两遍全表 `fetchSources()`（每条 JSONDecoder 解码）加一次无条件 `queue.write`，与 CloudSync 写者争锁 | reconcile 改为先读、有变化才写；整次加载共用一个读快照；解码结果按 `(id, updatedAt)` 缓存 |
| P6 | 中 | `Features/Library/Book/BookShelfViewModel.swift:42`、`BookReaderViewModel.swift:145` | `@MainActor` 上同步调用 `queue.read` 用例，阻塞主线程做 SQLite IO | 与漫画/视频线一致，经 actor 持久化协调器 |
| P7 | 中 | `Shared/UI/CoverImageView.swift:37-44`、`ImageRequestFactory.swift:51-63`、`BrowseCraftDomain/Diagnostics/RuleExecutionLogger.swift:12` | `body` 里每次渲染都构造 ImageRequest：扫 `HTTPCookieStorage`、合并 3 层 header、构造日志字典（Release 也求值） | 在 `.task(id:)` 里按 `(urlString, referer)` 算一次存 `@State`；logger 的 `fields` 改 `@autoclosure` |
| P8 | 中（仅生成路径） | `BrowseCraftCore/.../Parsing/Discovery/DefaultSourceDiscoveryAnalyzer.swift:175,296,339,390,424`、`DefaultSourceListStructureObserver.swift:61` | 同一份 HTML 被 `SwiftSoup.parse` 2-3 次 | 往下传 `Document` 而不是 `html: String` |
| P9 | 低 | `Infrastructure/Preflight/PreflightRenderedPageLoader.swift:56-60,100` | 每次预检新建 WKWebView + 非持久数据存储，固定睡 300 ms 再取快照 | 预检会话内复用 WKWebView 与数据存储；快照触发改静默窗口 |
| P10 | 低 | `BrowseCraftApp.swift:173` | `MobileAds.shared.start()` 在 `App.init` 同步跑，先于首帧 | 挪到已有的异步 `startApplicationServices()` |
| P11 | 低 | `Assets.xcassets/VideoDetailPlaceholder.imageset`（@3x 2.2 MB）、`Resources/Startup/startup-animation.mp4` 6.2 MB、`Resources/InAppPurchase/purchase-background.mp4` 5.7 MB | 包体与占位图解码尺寸 | 占位图按单元格分辨率导出；视频转 HEVC |
| P12 | 低 | `HistoryPersistenceCoordinator.swift:36-40` | 每条删除一个写事务 | 合并为一个事务 |
| P13 | 低 | `BrowseCraftCore/.../Parsing/Document/HTML/SwiftSoupHTMLDocumentParser.swift:104-114` | `selected.contains(where:)` + `isDescendant` 每个子节点一次，O(children × selected × depth) | `ObjectIdentifier` 集合 + 预计算祖先集 |

说明：P9 里 `configuration.processPool = WKProcessPool()` 在 iOS 15 之后没有任何效果，不会拉起新进程；该行本身就是警告组 F 的无效调用，真实成本只来自新建 WKWebView 与数据存储。

## 5. 修正清单

按建议实施顺序编号。每项标注影响范围与验证方式；标「触及影视线」的项按既定要求单独测量并真机复核。

### 阶段 0：闸门基线

| # | 修正 | 文件 | 验证 |
|---|---|---|---|
| F0-1 | 四个包 `Package.swift` 的 target 加 `swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]`（或 `-strict-concurrency=complete`），与 App 一致 | BrowseCraftCore/Domain/Runtime/APIKit 的 Package.swift | `swift build` 各包，记录新爆出的警告数作为基线 |
| F0-2 | `check-architecture-boundaries.sh` 的 import 正则改为 `^(@preconcurrency |@_exported )?import( (struct|class|enum|protocol|func|typealias))? (X)$`；三处（第 60、158、174 行附近）同改 | scripts/check-architecture-boundaries.sh | 跑脚本，确认现有 4 处 `@preconcurrency import BrowseCraftCore` 仍在允许层 |
| F0-3 | 脚本补 Features→Infrastructure、Shared→Application、Shared→Infrastructure 三个方向的类型引用检查；先把现有 15 处命中列为豁免清单，再逐个收敛 | 同上 | 脚本通过 |
| F0-4 | 脚本的 `print(`/`try!` 检查扩展到四个包的 Sources | 同上 | 脚本通过 |


实施记录（2026-09-18）：阶段 0 四项已完成。四个包的 library target 加了 `swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]`（`swift package dump-package` 确认生效）；边界脚本重写为覆盖全部 import 写法、新增三个引用方向、`declared_types` 识别 `@Observable` 等修饰、`print(`/`try!` 扩展到四个包；已有的 15 处引用命中与 Runtime 2 处字面量正则 `try!` 登记在 `scripts/architecture-boundary-exemptions.txt`。脚本清洁运行通过，7 项反向注入（`@preconcurrency import GRDB`、`import struct Nuke.…`、App 内 `try!`、包内 `print(`、Features 新引用 Infrastructure、删除任一豁免行）均按预期失败。`@Observable` 扩展未暴露新的命中。包侧严格并发基线（2026-09-18 授权 build 后，`swift package clean` 再 `swift build`）：Core、Domain、Runtime、APIKit 四个 library target 均为 **0 条警告**。在 APIKit 注入一个非 Sendable 全局 `let` 探针可得到 `MutableGlobalVariable` 警告，证明 `-enable-experimental-feature StrictConcurrency` 在 Swift 6.4 工具链上确实生效。

包侧修复（同日完成）：
- F1-1：Core `SourceRuntime: Sendable`（`Runtime/SourceRuntimeContract.swift`）；App 测试里两个录制替身 `RecordingSourceRuntime`、`AddComicRecordingRuntime` 补 `@unchecked Sendable`。App 侧 `LoadBookPublicationUseCase.swift:1,102` 两条警告随之消失，第 31 行的 `Date.init` 一条留给阶段 1（F1-2）。
- Core `Runtime/SourceRuntimeDataModels.swift` 四个值类型（`SourceReaderPageResource`、`SourceProtectedReaderImageReference`、`SourceProtectedReaderImageExecution`、`SourceLegacyProtectedReaderImageReference`）的 `@unchecked Sendable` 改为编译器校验的 `Sendable`，成员全部 Sendable，通过。
- APIKit `URLSessionPortalAPITransport` 的 `@unchecked Sendable` 改为 `Sendable`（唯一成员 `URLSession` 已是 Sendable），通过。
- Core 测试：`DefaultSourceDiscoveryAnalyzerTests` 的 `idGenerator` 闭包不再捕获修改局部 var，改用加锁计数器；testTarget `exclude: ["Fixtures"]` 消除 SwiftPM「12 个未处理文件」提示（fixture 由 `#filePath` 相对路径读取，不走 `Bundle.module`）。`swift build --build-tests` Core 与 APIKit 均 0 警告。
- 剩余 `@unchecked Sendable`：Core 三个私有 COW `Storage` 类、Domain `RuleRuntimeDebugLog`（NSLock 保护），均为合理用法，保留。

App 全量构建复核（`xcodebuild build-for-testing`，generic iOS 设备，不签名）：TEST BUILD SUCCEEDED。App 目标 39 条：相对 9 月 16 日清单少了 LoadBookPublicationUseCase 两条，多出 `Features/Library/Video/Player/VideoRuntimeAuditMediaEventHandler.swift:66,108,109` 四条（`#if DEBUG` 代码，WKScriptMessage 主线程属性在 nonisolated 回调里访问；该文件自 9 月 4 日未改，9 月 16 日是增量构建未重编译它，所以当时的日志没有列出）。真实基线因此是 41 而非 37，现为 39。测试目标另有 46 条（Xcode 普通 Build 不编译测试目标，所以之前未计入）：`#require` 冗余 24、`NSLock.lock/unlock` 在 async 上下文 10、`#require`/deprecated/未使用值等 12。这些进入阶段 1 的补充清单。

### 阶段 1：清零 37 条编译器警告

| # | 组 | 修正 | 文件 | 验证 |
|---|---|---|---|---|
| F1-1 | C | Core `SourceRuntime` 协议改为 `public protocol SourceRuntime: Sendable` | BrowseCraftCore/Sources/BrowseCraftCore/Runtime/SourceRuntimeContract.swift:5 | 三个实现已是 Sendable struct，包 build 无新警告；App 侧 LoadBookPublicationUseCase.swift:1,102 两条消失 |
| F1-2 | C | `now: @escaping @Sendable () -> Date = { Date() }` | BrowseCraft/Application/UseCases/Book/LoadBookPublicationUseCase.swift:31 | 警告消失 |
| F1-3 | D | 两个文件加 `import BrowseCraftDomain` | BrowseCraft/Shared/UI/CoverImageView.swift、ItemThumbnailImageView.swift | 4 条消失 |
| F1-4 | E | 两个 `ISO8601DateFormatter` 静态属性换成 `Date.ISO8601FormatStyle`（带/不带小数秒两个值），`date(from:)` 用 `try? Date(text, strategy:)` | BrowseCraft/Infrastructure/Generation/APIKitVideoGenerationOutcomesClient.swift:39-55 | 2 条消失；现有 outcomes 解析测试通过 |
| F1-5 | F | 删除 `configuration.processPool = WKProcessPool()` | BrowseCraft/Infrastructure/Preflight/PreflightRenderedPageLoader.swift:58 | 2 条消失 |
| F1-6 | A | `EPUBNavigatorRepresentable` 改用不带 `httpServer` 的 init；删除 `ReadiumBookEnvironment.httpServer` 与 `import ReadiumAdapterGCDWebServer`；`project.yml` 移除 `ReadiumAdapterGCDWebServer` product，重新生成工程 | Features/Library/Book/Reader/EPUBNavigatorRepresentable.swift:21-25、Infrastructure/Book/ReadiumBookEnvironment.swift:2,16、project.yml | 3 条消失；真机打开一本 EPUB 翻页正常 |
| F1-7 | A | 在 5 个 Readium 边界文件使用 `@preconcurrency import ReadiumShared` / `ReadiumNavigator`，声明 Readium 为前并发模块；`audioSpecifications` 随之不再告警 | AudiobookPlayerView、AudiobookRemoteControls、BookReaderViewModel、EPUBNavigatorRepresentable、ReadiumBookEnvironment | 需 build 确认 15 条 sending 警告被降级；若未降级，保留并记录为「等 Readium 标注 @MainActor」 |
| F1-8 | B | 先在真机用 `dispatchPrecondition(condition: .onQueue(.main))` 确认 UN 代理回调线程。若在主线程：两个方法体改为 `MainActor.assumeIsolated { ... }`，去掉 `DispatchQueue.main.async`。若不在：在 nonisolated 侧把 `userInfo` 抽成 Sendable 载荷结构，参数改 `@escaping @Sendable`，再 `Task { @MainActor in }` | BrowseCraft/BrowseCraftApp.swift:135-160 | 8 条消失；真机复现 09-05 的「前台收推送」与「点开推送」两条路径不崩、目录刷新 |

阶段 1 补充（2026-09-18 全量构建新发现）：

| # | 修正 | 文件 | 验证 |
|---|---|---|---|
| F1-9 | `userContentController(_:didReceive:)` 改为 MainActor 隔离（WKScriptMessageHandler 回调在主线程），或在 nonisolated 内先用 `MainActor.assumeIsolated` 取出 `name`/`body`；第 66 行 `withTaskGroup` 里 `@MainActor` 子任务改写为不依赖 region 检查的形式 | BrowseCraft/Features/Library/Video/Player/VideoRuntimeAuditMediaEventHandler.swift:66,108,109 | 4 条消失；audit 只随 Debug 编译 |
| F1-10 | 测试替身里 `NSLock.lock()/unlock()` 出现在 async 函数内的 10 处改为 `withLock {}` | BrowseCraftTests/TestDoubles/ViewModels/ScriptedSourceRuntime.swift、TestDoubles/Book/BookRuntimeTestDoubles.swift、Features/Library/Video/VideoPlayerViewModelHistoryTests.swift | 10 条消失 |
| F1-11 | 24 处对非可选 `URL(string: "字面量")` 的 `#require` 改为直接构造或 `XCTUnwrap`；`CoreRuleCandidateAnalyzerTests` 的 `nextID` 捕获改用与 Core 测试相同的加锁计数器；其余 deprecated/未使用值逐条清理 | BrowseCraftTests 下 12 个文件 | 测试目标 0 警告 |

实施记录（2026-09-18，阶段 1）：App 目标与测试目标 **均为 0 条编译器警告**（`xcodebuild build-for-testing`，generic iOS，Xcode 26 / Swift 6.4）。剩余两条非编译器提示为设计使然：广告测试单元提示与 AppIntents 元数据提示。边界脚本清洁。测试只编译未运行。

- F1-2/F1-3/F1-5：按清单落地。
- F1-4：`Date.ISO8601FormatStyle` 替换 formatter 静态实例。固定输入对照（`+00:00`、`Z`、`+0800`、带/不带小数秒、非法串）结果与原 formatter 一致，仅小数秒保留到微秒而非毫秒。
- F1-6：EPUB Navigator 改用不带 `httpServer` 的 init；`ReadiumBookEnvironment.httpServer` 与 `ReadiumAdapterGCDWebServer` 依赖一并移除，工程已重新生成。**待真机复核：打开一本 EPUB 翻页正常。**
- F1-7：五个 Readium 边界文件 `@preconcurrency import ReadiumNavigator` / `ReadiumShared`，15 条 sending 警告与 `audioSpecifications` 一条随之消失。
- F1-8：推送负载在系统回调的 nonisolated 上下文里先解成 Sendable 的 `RuleGenerationPushOutcome`（新增于 `Application/Push/RuleGenerationOutcomeRefreshRequests.swift`），再 `Task { @MainActor }` 处理并回调 completion；completion 参数声明为 `@Sendable`，编译器接受该 ObjC 协议 witness。语义与原 `DispatchQueue.main.async` 一致（completion 仍在主线程调用）。**待真机复核：前台收推送、点开推送两条路径不崩且目录刷新。**
- F1-9：`WKScriptMessageHandler` 在 SDK 里标为主 actor，去掉 `nonisolated` 后直接读消息、改状态；超时等待改为主 actor 上的守卫 Task 唤醒等待者，不再用 TaskGroup 竞速。
- F1-10：测试替身 5 处 `lock()/unlock()` 改 `withLock`。
- F1-11：24 处 `#require` 冗余——它们都出现在参数类型为 Optional 的位置，`#require` 无事可做：字面量 URL 直接构造（20 处），非字面量先 `#require` 绑定再传（3 处），`AnyURL.url` 本身非可选（1 处）。`readAsString()` 改 `read().asString()`；`HTTPURL ==` 改 `isEquivalentTo`；`is` 恒真改按存在类型断言；未使用值与游离字符串各一处。`TestSourceRuntimeResolver` 的工厂闭包改 `@Sendable`（resolver 本身 Sendable），随之修正两个测试里被捕获修改的局部变量与注册表（加锁标志 / 加锁注册表）。

### 阶段 2：性能（不触碰影视线共用默认值的项优先）

| # | 修正 | 文件 | 影响范围 | 验证 |
|---|---|---|---|---|
| F2-1 | Core 加正则缓存（按 pattern+options 键控、NSLock、有界），14 处调用点改走缓存 | BrowseCraftCore/Runtime 各解析文件 | 全 kind；纯加速，语义不变 | 固定输入测量：同一列表页解析前后耗时；Core 全量测试通过 |
| F2-2 | 注册 `ReaderImageDecoder` 为 Nuke decoder，移除 `ReaderImageProcessor` | Features/Library/Comic/Reader/ReaderPageImageView.swift:120、ReaderImageProcessing.swift、ImageCacheConfigurator | 漫画线 | 长条漫画阅读内存峰值前后对比；保护资源路径不变 |
| F2-3 | 封面/缩略图加 `.resize` 与 `ImagePrefetcher` | Shared/UI/CoverImageView.swift、ItemThumbnailImageView.swift、LibraryContentView.swift | 全 kind 列表 | 滚动帧率与缩略图缓存命中数 |
| F2-4 | ImageRequest 在 `.task(id:)` 构造一次；`RuleExecutionLogger.log` 的 `fields` 改 `@autoclosure` | 同上、BrowseCraftDomain/Diagnostics/RuleExecutionLogger.swift:12 | 全 kind | body 求值次数（Instruments SwiftUI） |
| F2-5 | reconcileSourceSlotAssignments 先读后写、整次加载单读快照 | Application/UseCases/Library/LibraryPersistenceCoordinator.swift、GRDBSourceRepository.swift:110 | 全 kind 列表 | 进列表的 SQL 次数与耗时 |
| F2-6 | 读书线两处同步读库改经 actor 协调器 | Features/Library/Book/BookShelfViewModel.swift:42、BookReaderViewModel.swift:145 | 读书线 | 主线程无 SQLite 调用（Main Thread Checker / Instruments） |
| F2-7 | WebView 稳定判定改 MutationObserver 静默窗口，窗口时长按请求声明，当前 500 ms + 6×300 ms 作基线；loader 复用 WKWebView | Infrastructure/Network/WKWebViewHTMLLoader.swift | **触及影视线**，单独做 | 固定站点集合测量 needsWebView 规则耗时；影视线真机复核 |
| F2-8 | 发现分析器传 `Document` 不传 `html` | BrowseCraftCore/Parsing/Discovery/DefaultSourceDiscoveryAnalyzer.swift、DefaultSourceListStructureObserver.swift | 仅规则生成 | 发现一次的 parse 次数从 3 降到 1 |
| F2-9 | `MobileAds.start()` 挪到 `startApplicationServices()` | BrowseCraftApp.swift:173 | 启动 | 首帧时间 |
| F2-10 | 预检复用 WKWebView 与数据存储 | Infrastructure/Preflight/PreflightRenderedPageLoader.swift | 规则生成预检 | 预检耗时 |
| F2-11 | 历史批量删除合并事务；占位图按单元格分辨率导出；视频转 HEVC；文本块提取用集合 | HistoryPersistenceCoordinator.swift、Assets、Resources、SwiftSoupHTMLDocumentParser.swift:104-114 | 低 | 包体与耗时 |

### 阶段 3：结构

| # | 修正 | 验证 |
|---|---|---|
| F3-1 | BrowseCraftDomain、BrowseCraftRuntime 各加 `Tests/` 与 testTarget，把 BrowseCraftTests 中只依赖包的用例迁入 | 两个包 `swift test` 可独立跑 |
| F3-2 | `DefaultRuleExtractionEngine.swift:10` 的 `SwiftSoupHTMLDocumentParser()` 默认构造改为注入 | Core 测试通过 |
| F3-3 | Core 拆为「规则模型」与「解析」两个 target；Domain 只依赖前者 | Domain 与 App 不再传递链接 SwiftSoup；增量编译时间对比 |
| F3-4 | 退役 `App/Compatibility/CoreRuleCandidateNaming.swift`，2 个外部使用者改直接 `import BrowseCraftCore` | build 通过 |

## 6. 附：编译器警告按文件计数

| 文件 | 条数 |
|---|---|
| BrowseCraftApp.swift | 8 |
| Features/Library/Book/Reader/AudiobookRemoteControls.swift | 5 |
| Features/Library/Book/Reader/AudiobookPlayerView.swift | 5 |
| Infrastructure/Book/ReadiumBookEnvironment.swift | 4 |
| Features/Library/Book/Reader/BookReaderViewModel.swift | 3 |
| Application/UseCases/Book/LoadBookPublicationUseCase.swift | 3 |
| Shared/UI/ItemThumbnailImageView.swift | 2 |
| Shared/UI/CoverImageView.swift | 2 |
| Infrastructure/Preflight/PreflightRenderedPageLoader.swift | 2 |
| Infrastructure/Generation/APIKitVideoGenerationOutcomesClient.swift | 2 |
| Features/Library/Book/Reader/EPUBNavigatorRepresentable.swift | 1 |
| 合计 | 37 |

按类别：RegionIsolation sending 17、SendableClosureCaptures 5、DeprecatedDeclaration 5、MutableGlobalVariable 3、AddPreconcurrencyImport 2、非 Sendable 函数值转换 1。
