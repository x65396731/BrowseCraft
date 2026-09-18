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

实施记录（2026-09-18，阶段 2 第一批：F2-1、F2-2）：

- **F2-1 正则缓存**：新增 `BrowseCraftCore/Sources/BrowseCraftCore/Support/RegularExpressionCache.swift`——按 `pattern + options` 键控、`NSLock` 保护、上限 512 条（超限整体清空）的进程级缓存，`regex(pattern:options:)` 与 `NSRegularExpression(pattern:options:)` 同签名、同错误语义。Core 与 Runtime 共 20 处临时编译点全部改走缓存（Core 13：提取引擎、视频/漫画/书解析器、模板解析、发现分析器、两套规则校验；Runtime 7：API 模板解析、视频检测、保护资源流水线与运行时）。`BookSourceRuntime` 两处 `static let` 字面量正则本就只编译一次，保持不变。固定输入测量（4 个规则里常见的 pattern 轮换、4000 次 = 25 页 × 40 条目 × 4 字段）：逐次编译 11.66 µs/次，缓存 0.95 µs/次，纯匹配 0.85 µs/次；即缓存后每次调用的开销≈纯匹配，一页列表少约 1.7 ms（Debug、M 系列 Mac；真机比例相同）。Core 全量测试目标编译通过（未运行）。
- **F2-2 降采样解码**：解码目标宽度成为 ImageRequest 上的显式声明（`ImageRequest.downsampleTargetPixelWidth`，`Shared/UI/DownsampledImageDecoder.swift`），共享 pipeline 的 `makeImageDecoder` 对声明了宽度的请求返回 `DownsamplingImageDecoder`（CGImageSource 缩略图接口按宽度解码，动图交还 Nuke 默认解码器），未声明的请求走默认解码器，行为不变。阅读器只在请求上声明宽度（`ReaderPageImageView`），`ReaderImageProcessor` 删除；受保护资源解密后的内存数据继续走同一个 `DownsampledImageDecoder.decode`，输出规格一致。固定输入测量（JPEG，目标宽 1179px）：源 2400×16000 时全尺寸解码再缩小 172 ms、缩略图解码 93 ms；源 3000×4200 时 54 ms 对 30 ms；源 1200×16000（≈目标宽）两者相同（168 对 184 ms，噪声内）。中间位图：全尺寸路径 2400×16000×4 ≈ 154 MB，缩略图路径直接输出 1179×7860×4 ≈ 37 MB；收益与「源宽/目标宽」的平方成正比，源宽≈目标宽时无收益也无损失。已知取舍：解码后的内存缓存键不含目标宽度（当前只有阅读器使用、宽度为屏幕宽度，横竖屏切换复用另一宽度位图仅影响缩放质量），已在代码注释中声明。**待真机复核：长条漫画阅读内存峰值前后对比、GIF 页仍可播放、受保护资源页正常。**

实施记录（2026-09-18，阶段 2 第二批：F2-3、F2-4）：

- **F2-4 请求只构造一次**：新增 `Shared/UI/RemoteImageRequestBuilder.swift`——`RemoteImageRequestIdentity`（地址、Referer、规则请求配置、附加头、显示尺寸）作为 `.task(id:)` 的标识，`CoverImageView` 与 `ItemThumbnailImageView` 只在标识变化时构造一次 `ImageRequest`（扫 Cookie 存储、合并三层请求头、写日志），不再在 `body` 里随每次渲染重复。`RuleExecutionLogger.log` 的 `fields` 改为 `@autoclosure`，42 处调用点不变，Release 下字典字面量不再求值。
- **F2-3 按单元格尺寸解码**：视图用 `onGeometryChange` 测得布局尺寸后，在请求上声明 Nuke 自带的 `thumbnail` 选项（`userInfo[.thumbnailKey]`，`aspectFill`，pt 单位），默认解码器在解码阶段用 CGImageSource 缩略图接口按尺寸降采样；Nuke 的内存缓存键包含该选项（`Internal/ImageRequestKeys.swift` 的 `MemoryCacheKey`），同一地址在不同尺寸的位置各自解码、互不串用，磁盘数据缓存键不变、不重复下载。没有测到尺寸的视图按原图解码，行为与之前一致。之前设想的 `.resize` processor 不再需要：processor 在全尺寸解码之后才运行，缩略选项在解码时就生效，且是 Nuke 自带的通用机制，不引入项目自有 processor。
- **预取（F2-3 后半）暂缓**：`LazyVGrid` 本就提前实例化下一屏单元格，`LazyImage` 随之开始加载；显式 `ImagePrefetcher` 需要在单元格存在前就算出带请求头与尺寸的请求，收益未经测量前不加机制。列为后续项，待真机滚动帧率与缓存命中数据。
- 收益估算（沿用 F2-2 的固定输入测量方法）：缩略图单元格 64×88pt（@3x 约 192×264px）对 600×900 的封面，解码像素从 54 万降到约 5 万，内存缓存里一张封面从约 2 MB 降到约 0.2 MB，64 MB 上限可容纳约 300 张而非约 30 张。**待真机复核：列表滚动帧率、缩略图缓存命中率、详情页封面清晰度（大图位置测得尺寸大，解码尺寸随之变大）。**

实施记录（2026-09-18，阶段 2 第三批：F2-5、F2-6）：

- **F2-5 列表加载读写收敛**（`Infrastructure/Database/Repositories/GRDBSourceRepository.swift`、`Records/Source/SourceRecord.swift`、`Application/UseCases/Source/SyncBuiltInSourcesUseCase.swift`）：
  - `SyncBuiltInSourcesUseCase.execute()` 在目录为空时直接返回。当前所有装配点（Library / Sources 工厂）都以默认空目录构造它，此前每次进列表都白读一遍并解码全部来源。
  - `reconcileSourceSlotAssignments()` 改为先读后写：读事务里判断「用户行存在且没有来源需要翻转启用状态」，成立则直接返回同一次读事务里解出的来源；否则才进入原有写事务（含 `insertUser`、翻转、清选择、入同步队列），保持「归置后用户行必定存在」与「有变化才通知 CloudSync」两条不变量。读判断与写归置共用同一份候选 SQL 与槽位上限计算。
  - `SourceRecord.sourceConfiguration()` 经 `SourceConfigurationDecodingCache`（用户 + id 键控、JSON 原文逐字比对命中、有界 256 条）解码，Library / History / Favorites / Sources 每次进页面解码全部来源的重复 `JSONDecoder` 被消掉；JSON 变了即失效，无陈旧风险。
  - 每次进列表的数据库事务：之前 1 读（sync）+ 1 写（reconcile）+ 1 读（fetchSources）+ 收藏读 + 状态读；之后 1 读 + 收藏读 + 状态读，稳态下不再开写事务、不再与 CloudSync 写者争 WAL 写锁，来源 JSON 解码从每次 2N 次降到 0 次（命中）。
- **F2-6 读书线读库离开主线程**（`Application/UseCases/Book/BookPersistenceCoordinator.swift`）：新增 `BookShelfPersistenceCoordinator`（列本地书）与 `BookReaderPersistenceCoordinator`（续读位置、书签列/加/删）两个 actor，与 Library / History / Favorites 同一模式；`BookShelfViewModel.load()`、`BookReaderViewModel` 的续读位置读取、书签加载与增删改为 `async` 经 actor 执行，视图与测试调用点相应 `await`。VM 的 init 签名不变（actor 由 VM 用注入的用例构造），工厂与三个测试文件无需改装配。进度节流落库（`persistCurrentLocation` / `flush`）保持同步：离开阅读器时 flush 必须立即完成，且测试断言依赖其同步语义；它是单行 upsert，留作后续观察项。
- 验证：App 与测试目标构建通过、0 警告，边界闸门干净；测试只编译未运行。**待真机复核：进列表 / 历史 / 收藏的耗时（Instruments SQLite 事务数），书架、书签增删、续读位置正常。**

实施记录（2026-09-18，阶段 2 第四批：F2-8、F2-9、F2-12、F2-13；F2-10、F2-11 判定不动；F2-7 待专项）：

- **F2-8 发现分析只解析一次**：`DefaultSourceDiscoveryAnalyzer` 的列表/详情/阅读/分页四个子分析改为接收 `Document` 而非 `html: String`，与主分析共用一份解析结果。前提已核对：四处原本都以 `input.document.finalURL` 作 base URL，且子分析对 DOM 只读不改（全文件无 remove/empty/attr 写入调用）。同一页的 SwiftSoup 解析次数从 2 到 3 次降到 1 次。`DefaultSourceListStructureObserver` 是独立公开入口，保持不变。
- **F2-9 广告 SDK 延后启动——已回退**：曾把 `MobileAds.shared.start()` 从 `App.init` 挪到主界面出现后。模拟器冒烟检查发现回归：Crashlytics 在启动日志里报 7 条 `The signal SIGABRT has a non-Crashlytics handler (GADRegisterSignalHandlers)`（旧构建 0 条）——广告 SDK 晚于 Crashlytics 启动时会用自己的信号处理器覆盖 Crashlytics 的，信号类崩溃将无法上报。`disableSDKCrashReporting()` 只关异常处理器、管不到信号处理器（实测仍 7 条）。因此恢复到 `App.init` 里启动，并把「广告 SDK 必须早于 `FirebaseApp.configure()`」写成代码注释里的顺序不变量；恢复后警告 0 条。首帧收益让位于崩溃上报的正确性。
- **F2-12 历史批量删除合并事务**：四个历史仓库协议新增 `delete(_ histories: [T])`，协议扩展给出逐条默认实现（测试替身零改动），GRDB 实现在一个写事务里循环 DELETE；`DeleteReadingHistoryEntryUseCase` 新增按表分组的批量入口，`HistoryPersistenceCoordinator.delete` 改用它。清理 N 条历史从 N 个写事务降到最多 4 个。
- **F2-13 文本块提取用集合**：`SwiftSoupHTMLDocumentParser.orderedTextBlocks` 先一次性算出被选节点与其全部祖先两个 `ObjectIdentifier` 集合，遍历时每个子节点 O(1) 判断；原为 O(children × selected × depth)。
- **F2-10 判定不动**：`PreflightRenderedPageLoader` 的文档明确声明「每次取样各自一个非持久数据存储与 WKWebView，互不共享 Cookie / 凭据 / 导航状态」是隔离不变量，复用 WebView 会破坏它；`processPool` 一行已在阶段 1 删除。剩余的固定 300 ms 快照延迟与 F2-7 是同一机制（静默窗口），并入 F2-7 专项。
- **F2-11 已于同日测量并部分实施**：启动动画本就是 HEVC 且音轨有意播放（不动）；内购背景转 HEVC 省 4.46 MB（已做）；占位图逐张核算后只有两张列表图约 1.6 倍过大。详见第 5.4 节。
- **F2-7 已于同日专项测量并关闭**：前提被固定输入测量推翻，详见第 5.1 节。
- 验证：Core/Runtime 构建、Core 测试目标编译、App 与测试目标构建均通过、0 警告，边界闸门干净。模拟器（iPhone 17 Pro，iOS 26.5）冒烟：正常签名的 Debug 包引导成功、启动动画播放、进程稳定；配合 `-BrowseCraftSkipStartupAnimation` 与新增的 `-BrowseCraftInitialTab <标签>` 逐页检查了五个 tab（来源、收藏、库、历史、设置），全部渲染空态、无崩溃、无应用级报错（唯一 error 是未登录 Apple 账号的 `session-load result=failed`，属预期）；用 `CODE_SIGNING_ALLOWED=NO` 构建的包会在引导阶段以 `KeychainAppUserIdentityStoreError` 失败（无 application-identifier 时 Keychain 写入被拒），属于构建方式问题、不是代码回归——顺带发现引导失败页只把错误类型名哈希成诊断码、底层 OSStatus 没有进任何日志，列为后续项。**待真机复核：规则生成的发现分析结果与改前一致（同一页候选集合相同）、清空历史。**

### 阶段 3：结构

| # | 修正 | 验证 |
|---|---|---|
| F3-1 | BrowseCraftDomain、BrowseCraftRuntime 各加 `Tests/` 与 testTarget，把 BrowseCraftTests 中只依赖包的用例迁入 | 两个包 `swift test` 可独立跑 |
| F3-2 | `DefaultRuleExtractionEngine.swift:10` 的 `SwiftSoupHTMLDocumentParser()` 默认构造改为注入 | Core 测试通过 |
| F3-3 | Core 拆为「规则模型」与「解析」两个 target；Domain 只依赖前者 | Domain 与 App 不再传递链接 SwiftSoup；增量编译时间对比 |
| F3-4 | 退役 `App/Compatibility/CoreRuleCandidateNaming.swift`，2 个外部使用者改直接 `import BrowseCraftCore` | build 通过 |


实施记录（2026-09-18，阶段 3）：

- **F3-3 Core 拆为两个 target**：`BrowseCraftCore` 包新增 `BrowseCraftRuleModels` target（`Rule/`、`Source/`、`Runtime/`、`Diagnostics/`、`Serialization/`、`Support/`、`Document/`，纯 Foundation），`BrowseCraftCore` target 只剩 `Parsing/` 并 `@_exported import BrowseCraftRuleModels`，因此 App、Runtime 的 `import BrowseCraftCore` 与模块限定名 `BrowseCraftCore.X` 全部不变。编译驱动地把三样被模型侧引用的东西挪进模型层：`LegacyComicExpressionAdapter` / `LegacyComicListRuleAdapter`（迁移操作用）、`SourceParsingError`（模型与解析共用的错误合同）、`SourceContentDocument`（文档数据模型）。交叉引用原本就全是 public，无需 `package` 访问级。`BrowseCraftDomain` 改为只依赖 `BrowseCraftRuleModels` 产品（10 处 import 与 4 处限定名改名），不再链接 SwiftSoup。边界脚本新增闸门：`BrowseCraftRuleModels` 目录禁止 `import SwiftSoup` 与 `import BrowseCraftCore`（反向注入验证会失败）。Core、Domain、Runtime、App 与测试目标全部 0 警告构建通过。
- **F3-2 判定不再需要**：`DefaultRuleExtractionEngine` 与 `SwiftSoupHTMLDocumentParser` 同在解析 target，默认构造不跨模块；SwiftSoup 的 import 白名单未变。
- **F3-1 测试目标**：前提测量否定了「迁移只依赖包的用例」——104 个 App 测试文件里 101 个 `@testable import BrowseCraft`。因此改为新建 `BrowseCraftDomainTests`（Cookie 合并策略 5 例）与 `BrowseCraftRuntimeTests`（检测词典资源随包发布与加载 4 例、模板地址切片 2 例），三包 `swift build --build-tests` 通过；`RegularExpressionCache` 在 Core 测试里补 4 例。App 侧用例的迁移需要先把它们对 App 类型（`SourceDefinitionMapper`、`TestSourceRuntimeResolver` 等）的依赖改掉，列为后续项。
- **F3-4 退役别名**：`App/Compatibility/CoreRuleCandidateNaming.swift` 的 13 个 typealias 删除，3 个使用文件改用 Core 原名（`SourceRuleCandidate*`、`SourceRuleCandidateDraftApplier`），文件只保留 App 需要的 Core 类型扩展。
- 测试运行结果（2026-09-18，用户授权后）：`swift test` Core 228 例（4 例按设计跳过）、Domain 5 例、Runtime 6 例、APIKit 通过，全部 0 失败；App 测试套件在 iPhone 17 Pro（iOS 26.5）模拟器上 XCTest 39 例 + Swift Testing 493 例（86 个套件）全部通过。Runtime 新用例里一处反例假设有误（带空格字符串在新版 Foundation 仍可构成 URL），已改为根地址反例。


模拟器验证辅助（2026-09-18）：`App/RootView.swift` 新增 DEBUG 专用启动参数 `-BrowseCraftInitialTab <标签>`，标签即 `RootTab` 的原始值（sources/favorites/library/history/settings），跳过开屏后停在指定 tab。它与既有的 `-BrowseCraftSkipStartupAnimation` 同一模式、同为 `#if DEBUG`，Release 不含；新增 tab 无需改动该参数的实现。引入原因：模拟器注入 tap 需要设备授权，而该授权在本次会话中未获响应。


## 5.1 F2-7 专项结论（2026-09-18）：前提被测量推翻，条目关闭

固定输入测量（`BrowseCraftTests/Infrastructure/Network/WKWebViewDOMStabilityMeasurementTests.swift`，
`loadHTMLString` 注入合成页面，不访问真实站点，iPhone 17 Pro / iOS 26.5 模拟器）：

| 测量项 | 结果 |
|---|---|
| 安静小页面的基线等待 | 1,553 ms，6 轮观察 |
| 正文延迟 800 ms 写入时的基线等待 | 1,872 ms，7 轮；返回时正文已在 DOM 里（长度 4,208） |
| 离屏 WebView 内 `setTimeout(50ms)` 的实际间隔 | 153 ms |
| 662 KB DOM 上 6 次整页 `outerHTML.length` | 合计 7 ms（扣掉 6 次空调用后净开销 6 ms） |

三条结论，推翻了审计第 4.2 节 P1 的两个前提：

1. **那约 1,500 ms 不是浪费，是一条没写下来的不变量。** 页面可能在 `didFinish` 之后先安静一段，再用定时器写入正文。
   「最少观察 6 轮」形成的下限恰好盖住这种情况。实测：把判定改成「连续 300 ms 无变更即稳定」后，
   在正文 800 ms 才出现的页面上 **307 ms 就判定稳定并会交出空正文**。削减这条下限是正确性回归，不是优化。
2. **整页 DOM 序列化不构成开销。** 原以为「每轮序列化整棵 DOM」是主要成本，实测 662 KB 的文档 6 次合计 6 ms。
   按此量级，去掉它最多省下个位数毫秒。
3. **离屏 WKWebView 会节流页面内的定时器**（请求 50 ms、实际 153 ms），因此任何「把等待循环放进页面」的方案
   都无法稳定控制节奏；判定节奏必须留在 Swift 侧。实测中基于页面内计时的静默窗口在 5 个夹具里有 3 个比基线更慢。

因此 **F2-7 关闭，不做机制替换**。本次保留三项成果：

- `Infrastructure/Network/WKWebViewDOMStability.swift`：把原先埋在 `WKWebViewHTMLLoader` 私有常量里的判定策略
  提成显式声明值 `WKWebViewDOMStabilityPolicy`，由装配点（`SourceRuntimeComposition`）写明使用 `.baseline`；
  `minimumObservationChecks` 上写明它是晚到内容的保护下限。此前这组数字没有任何地方说明其作用。
- 上述测量用例常驻，把两条不变量固化为闸门：判定稳定的时刻不得早于正文写入；序列化开销维持在个位数毫秒量级。
- `project.yml`：测试目标补上 `BrowseCraftRuleModels` 产品依赖。这是 F3-3 拆分留下的真实缺口，此前被未重新生成的
  工程文件掩盖，重新生成后表现为 `PaginationRule` 等符号链接失败。

唯一还可能有收益的方向已于同日实现并测量（见 5.5 节）：把「稳定」的判据从「DOM 不再变化」换成
「规则自己的选择器已能取到节点且数量稳定」。机制以 `PageLoadRequest.readinessSelector` 这个 Domain 端口字段
表达，跨层边界由此收口；Runtime 尚未填值，影视线行为未变。


## 5.2 引导失败诊断（2026-09-18）

起因：本次会话在模拟器上遇到一次引导失败，页面只给出 `BOOT-FD717BA7D8AB6500`。该诊断码仅由**错误类型名**
做 FNV 哈希而来，底层原因不进任何日志，只能把代码库里所有错误类型名逐个哈希去反推，才对上
`KeychainAppUserIdentityStoreError`；而它携带的 `OSStatus`（真正原因）在任何地方都看不到。用户报一个码过来，
排查路径完全相同。

改动（`Shared/Diagnostics/ErrorDiagnostics.swift`）：

- 新增 `DiagnosticSummaryProviding`：**由错误类型自己声明可安全记录的摘要**。不实现它的错误只记类型名与
  `NSError` 的 domain:code。之所以不直接 dump `String(describing:)`：任意错误的描述里可能带 Cookie、token、
  授权头、设备标识、密钥材料或用户路径，AGENTS.md 明确禁止记录。由类型自己声明，等于把「什么可以外泄」
  变成显式、可审阅的决定。摘要仍过一遍既有的 `AppLog.sanitizedDebugMessage` 脱敏。
- 两处声明：`KeychainAppUserIdentityStoreError` 交出 `OSStatus`（只状态码，不含 service / account / 条目内容）；
  `GRDB.DatabaseError` 交出 SQLite 结果码与扩展结果码（不含 SQL 文本与绑定参数）。
- `AppBootstrapFailure` 增加 `diagnosticDetail`，诊断码本身保持不变（对用户是稳定引用）；
  `AppBootstrapState.bootstrap` 的 catch 里以 `startup` 分类记一条 `bootstrap-failed`，内容与页面可复制的一致。
- 失败页增加「Copy Diagnostics」按钮，整段复制码与摘要，省掉用户转述。

端到端复核（未签名构建正好复现该失败）：日志现在直接给出
`type=BrowseCraft.KeychainAppUserIdentityStoreError code=…:0 detail=unexpectedStatus(-34018)`
（-34018 即 `errSecMissingEntitlement`），与此前靠反推得到的结论一致。失败页按钮渲染正常。

测试：`AppBootstrapFailureTests` 补 3 例，分别守住「未声明摘要的错误负载不进诊断信息」（默认安全）、
「声明了摘要的错误状态码必须可见」、以及 Keychain 那一条。

顺带修掉一处测试稳定性问题：F2-7 的测量用例创建的 WKWebView 未释放，一次全量运行里测试宿主被 SIGKILL
（`Test crashed with signal kill`），随机牵连到当时正在跑的 `VideoGenerationPreflightArchiveFixtureTests`。
已加显式 tearDown 释放 WebView 并把大 DOM 夹具从 4000 行缩到 1500 行；重跑全量通过。


## 5.3 边界豁免收敛（2026-09-18）

F0-3 建闸门时登记了 11 条现存命中作为基线。本次把 **Features → Infrastructure 这一整个方向的 7 条全部消掉**，
删除豁免后重跑闸门仍然干净，并做了反向注入验证（Features 重新引用 `ReadiumSitePublicationBuilder` 会失败）。

按命中性质分三类处理，而不是一律套同一种改法：

1. **确实该走 Application 端口的（1 条）**：`SettingsViewModel` 直接持有 `ImageCacheConfigurator`。
   新增端口 `Application/Ports/Settings/ImageCacheManaging.swift`，只声明界面真正用到的三个动作
   （应用设置、按新上限裁剪、清空），`ImageCacheConfigurator` 实现它，装配点注入。
   端口**刻意不标 `@MainActor`**：标了会让实现类型整体被推断为主 actor 隔离，而它内部有磁盘裁剪的队列工作
   （实测会产生 `call to main actor-isolated static method in a synchronous nonisolated context` 警告）。
2. **分类本身放错了的（3 条）**：两个 `Bundled*AnimationResource` 只是从 App bundle 里按名字找资源，
   没有网络、数据库、keychain 这类副作用，和 `Shared/UI` 里直接读资产目录的代码同一性质。
   已从 `Infrastructure/{InAppPurchase,Startup}` 归位到 `Shared/Resources`，三处引用随之合规，无需任何注入管道。
3. **需要依赖倒置的（2 条）**：`BookReaderViewModel` 引用 `ReadiumSitePublicationBuilder` 与
   `ReadiumBookPublicationHandle`。这两条没有现成的落点——Application 明确禁止 `import Readium`，
   而 Shared 不得引用 Application 类型（协议签名里要用 `BookPublicationManifest`）。
   因此由阅读器自己声明 `SiteReadiumPublicationBuilding` 与 `ReadiumPublicationProviding`
   （`Features/Library/Book/Reader/BookReaderPublicationPorts.swift`），符合性写在唯一同时认识两层的装配根
   （`App/Composition/ReadiumPublicationCompositionAdapters.swift`）。阅读器对句柄的向下转型改为转到协议。

另有 1 条随阶段 1 的改动自然失效：`EPUBNavigatorRepresentable` 对 `ReadiumBookEnvironment` 的引用在去掉
本地 HTTP 服务后已不存在，直接删除。

同时补上 F3-3 拆分的另一半缺口：**应用目标**也要显式链接 `BrowseCraftRuleModels` 产品（界面层直接用到
`BookReaderRule` 等类型）。此前只补了测试目标；重新生成工程后应用目标同样链接失败。

接着（同日第二批）把 Shared 的两个方向也收敛掉，豁免清单降到 1 条：

- **错误分类器下沉**：`RuleExecutionErrorClassifier` 从 `Shared/Errors` 移到 `Application/Diagnostics`。
  它的分支要认 `CatalogSourceImportError` 与 `SourceListLoadValidationError`（Application 类型），
  而 Application 自己也用它（`ValidateSourceListLoadUseCase`），所以既不能留在 Shared 也不能搬去 Features。
  归位后两个方向同时成立。文件名同时纠正为类型名（原名 `RuleExecutionError.swift` 误导，那个枚举在 Domain）。
- **上报入口不再自己分类**：移动后暴露出同方向的第二处引用——`Shared/Diagnostics/AppAnalytics.swift`
  也在调分类器，只为在两个 Firebase 事件桶之间选一个。改为 Shared 只接收已判定的 `DiagnosticFailureKind`
  （新增于 `Shared/Diagnostics/DiagnosticEnums.swift`，纯取值、不含判定），判定逻辑归到分类器的
  `diagnosticFailureKind(for:)` 一处，13 个 Features 调用点随之改传类别。
- **缩略图缓存池改注入**：池子与请求改写都带 Nuke 类型，进不了 Application 端口；新增
  `ItemThumbnailImagePipelineProviding` 与 Environment 键（`Shared/UI/ItemThumbnailImagePipelineEnvironment.swift`），
  与本层既有的请求头 provider 同一模式，装配根注入 `ItemThumbnailImageCachePlugin.shared`。
  协议需声明 `Sendable`，否则 `EnvironmentKey.defaultValue` 在严格并发下报非并发安全。

反向注入验证：Shared 重新引用 `CatalogSourceImportError` 或 `ItemThumbnailImageCachePlugin` 均按预期失败。

**豁免清单现仅剩 1 条**：Runtime 两处字面量正则 `try!`（模式固定不会失败）。建议长期保留为已审阅例外——
清单归零后，任何新命中都是真正的新违规，闸门才真正起作用。

期间遇到一次 `Test crashed with signal kill before establishing connection`（测试宿主在建立连接前被杀），
重启模拟器后全量通过；与代码改动无关，属今天多次运行后的模拟器资源状态。

验证：App 与测试目标 0 警告；模拟器全量 XCTest 43 例 + Swift Testing 496 例通过；闸门干净且反向注入会失败。


## 5.4 资产瘦身（2026-09-18）：F2-11 的判定被测量部分推翻

审计第 4.2 节 P11 与 5.1 节把这条记为「判定不动」，理由是「占位图尺寸接近最大显示分辨率」「两段 mp4 转 HEVC 约减半」。
实测两条都需要修正。

**两段视频：只有一段需要转。**

| 资产 | 原编码 | 尺寸 / 时长 | 结论 |
|---|---|---|---|
| `startup-animation.mp4` | **已是 HEVC** 720×1280 24fps 3.3Mbps | 6.2 MB / 15.1s | 不动。它还带一条 128kbps AAC 音轨，而 `StartupVideoPlayerView` 显式设 `isMuted = false`、`volume = 1` 并激活 ambient 会话，**音轨是有意播放的，不能剥** |
| `purchase-background.mp4` | H.264 1080×1920 30fps 5.9Mbps | 5.94 MB / 8.07s | 转 HEVC |

内购背景的转码对照（`ffmpeg -c:v libx265 -tag:v hvc1 -an`，SSIM 对原片）：

| 编码 | 字节 | 相对源 | SSIM |
|---|---|---|---|
| 源 H.264 | 5,936,112 | 100% | - |
| HEVC CRF 28 | 1,479,380 | 25% | 0.9902 |
| HEVC CRF 30 | 1,187,453 | 20% | 0.9886 |
| HEVC CRF 34 | 787,452 | 13% | 0.9838 |

取 **CRF 28**（三者中画质最高，仍省 75%）：**包体减少 4.46 MB**。同时抽同一帧做了肉眼对照，无可见差异。
`avconvert` 的 HEVC 预设在本机不可用，改用 libx265 并打 `hvc1` 标记以保证 iOS 播放。

**占位图：原判定基本成立，但理由不同。** 逐张按实际显示尺寸核算后：

- `VideoDetailPlaceholder` @3x 1320×1386 —— 显示为全屏宽 × 宽×1.05，430pt 设备 @3x 即 1290×1355，**尺寸正好**，不该缩。
- `ComicDetailPlaceholder` @3x 354×504 —— 小图位（118×168pt）正好；但它同时用在全宽 × 330pt 的大图位上，
  那里其实是**被放大**的，属另一类问题（清晰度），不是体积问题。
- `ComicListPlaceholder` / `VideoListPlaceholder` @3x 600×900 —— 三列网格单元约 125pt 宽，@3x 约 375×562，
  **约 1.6 倍过大**，缩到 400×600 合计约省 1 MB。这一步要重采样美术资产，留给你决定，不由我改。

### 5.4.1 占位图（2026-09-18 续）：判定被两轮测量连续推翻，最终省 2.63 MB

这一项的结论改了三次，每次都是被测量推翻的，过程本身比结论更值得记下来。

**第一次推翻：尺寸不是问题。** 动手前按两个网格的实际版面重算——两处都是固定 3 列、12pt 间距、
16pt 外边距，单元宽度是 `(屏宽 − 56) / 3`：

| 设备 | 屏宽 | 单元宽 | 需要像素 | 当时提供 |
|---|---|---|---|---|
| iPhone SE | 375 | 106pt | @3x 319 | @3x 600 |
| iPhone 17 Pro Max | 440 | 128pt | @3x 384 | @3x 600 |
| iPad 11" 竖 | 834 | 259pt | @2x 519 | @2x 400 |
| iPad 13" 横 | 1366 | 437pt | @2x 873 | @2x 400 |

工程是通用 App（`TARGETED_DEVICE_FAMILY: "1,2"`），iPad 取 @2x 档，所以 **@2x 那一档今天已经在被放大 2.2 倍使用**。
按上一条「缩到 400×600」会让 iPad 更糊。真正没有收益的是**多档 scale 槽位本身**：
四张占位图一律经 `ItemThumbnailImageView` 的 `.resizable().scaledToFill()` 缩放到版面框，
@1x/@2x 两档不产生任何收益。

**第二次推翻：换 HEIC 是错的。** 先按「四张都转单档 HEIC」做了一版，源文件从 8,045,563 降到 1,783,029 字节，
看起来省 6.26 MB。但源文件不是随包的东西——`actool` 会把资产解码后按自己的格式重编码，
所以必须量编译产物 `Assets.car`。量完结论反转：

| 方案 | Assets.car | 相对原始 |
|---|---|---|
| A 原始三档 PNG | 6,353,656 | — |
| B 单档 HEIC | 4,243,784 | 省 2.11 MB |
| C 单档 PNG（只砍槽位） | 4,202,168 | 省 2.15 MB |
| D 单档 PNG + `"compression-type": "lossy"` | 3,367,784 | 省 2.99 MB |
| E 单档 HEIC + lossy 标记 | 4,243,784 | 标记对 HEIC 无效 |

收益几乎全部来自砍掉冗余槽位；**HEIC 反而比 PNG 大 41 KB，还白丢了画质**，已放弃。
真正的杠杆是资产目录自带的 `compression-type: lossy`，而且它作用在无损 PNG 源上，
以后再调整不会把有损叠加在有损上。给启动屏也标 lossy 试过，`Assets.car` 反而大 86 KB，所以启动屏不标。

**第三次修正：lossy 不能一刀切。** 用一条一次性用例把编译进 App 的资产解码回磁盘，
在每张图**真实的渲染宽度**上算 SSIM：

| imageset | 真实渲染宽度 | lossy 后 SSIM | 结论 |
|---|---|---|---|
| ComicListPlaceholder | iPhone 387px | 0.9979 | lossy |
| VideoListPlaceholder | iPhone 387px | 0.9975 | lossy |
| ComicDetailPlaceholder | 小图位 354px | 0.9902 | lossy |
| VideoDetailPlaceholder | 全宽 1290px（原生 1320px） | 0.9643 | **保持无损** |

规律很清楚：**渲染宽度远小于原生分辨率时，缩放本身就抹平了压缩块**，所以 lossy 几乎无损失；
而视频详情那张是按接近原生分辨率铺满整屏的详情页主视觉，0.964 是看得见的。
它单独保持无损多花 358,656 字节。

**最终取值**：四张都改为单档，三张标 lossy，视频详情保持无损。
`Assets.car` **6,353,656 → 3,726,440 字节，省 2.63 MB**（同一套 `actool` 参数下的对照）。
模拟器实际构建产物经设备瘦身后是 3,683,496 字节，与对照一致。按 387px 渲染后肉眼核对无可见差异。

**新增两层闸门，共用一份显式声明**（`scripts/bundled-image-asset-budgets.txt`，把上面三轮测量的取值固化成基线）：
- 构建前 `scripts/check-bundled-image-assets.sh`（已接入 `preBuildScripts`）——每个 imageset 必须登记，
  源字节不超上限，形态与像素尺寸符合声明，lossy 标记与形态双向一致（该有的必须有，不该有的不许有）。
  用五种反证验过：塞回 PNG 槽位、新增未登记 imageset、声明写错尺寸、拿掉该有的 lossy、给无损那张标 lossy。
- 运行期 `BundledImageAssetTests` ——编译进 App 后每张资产还能解出 `CGImage` 且像素尺寸与声明一致。
  这一层不可省：资产目录接受一种格式不等于运行期解得出，解不出的表现是占位图一片空白，既不崩溃也不报错。
  同样用反证验过（把声明尺寸改错一位，用例失败）。

## 5.5 WebView 就绪选择器（2026-09-18）：机制已实现并测量，Runtime 已消费 `ready` 字段，模拟器已验证整链

第 5.1 节关闭 F2-7 时留下的唯一可行方向。它把「页面稳定了没」换成「规则要提取的东西到了没」，
因而既去掉盲等，又不丢晚到的内容。

**机制**（`BrowseCraftDomain/.../PageLoadRequest.readinessSelector` + `WKWebViewDOMStability.swift`）：
- 调用方可在 `PageLoadRequest` 上声明一个普通 CSS 选择器，含义是「有命中且数量稳定 ⇒ 内容已在 DOM 里」。
  `nil` 时行为与引入前逐字相同。
- 加载器在同一个采样循环里评估两个条件：选择器有命中且连续两次采样数量相等 → 提前返回（`selectorReady`）；
  否则沿用历史机制的长度判定（观察下限、连续稳定次数、最大轮数、间隔全部逐字保留）。
  **选择器只是加速条件**，始终不命中时退回历史判定，因此不会比不声明更慢。
- 采样是一次往返同时取「命中数 + 整页长度」；计时留在 Swift 侧（离屏 WebView 会节流页面内定时器，见 5.1）。
- 选择器非法时命中数记 -1、按未命中处理，不让一个坏选择器把整次加载变成错误；选择器经 JSON 编码注入，不拼接进脚本。
- 「数量稳定」而非「首次命中」，是为了让分批追加的列表把这一批追加完。

**固定输入测量**（`WKWebViewReadinessSelectorMeasurementTests`，5 例常驻，同时是闸门）：

| 夹具 | 不声明（基线） | 声明 `.item` | 说明 |
|---|---|---|---|
| 静态列表页（3 条） | 1,558 ms | **321 ms** | 两次采样即返回 |
| 800 ms 后才写入条目 | 1,874 ms | **1,231 ms** | 返回时 3 条已在 DOM 里（用例断言） |
| 每 250 ms 追加一条、共 5 条 | 2,481 ms | **1,571 ms** | 返回时命中数等于 DOM 实际数量 5 |
| 空列表页（永不命中） | 1,575 ms | 1,563 ms | 退回历史判定，无回归 |
| 非法选择器 `li[` | 1,549 ms | 1,570 ms | 等价于未声明，不报错 |

三条被守住的不变量：声明选择器永远不比不声明慢（差值在计时抖动内）；内容出现之前不返回；非法选择器等价于未声明。

**Runtime 接线（同日第二步）**：先回答「三种 kind 先给谁」。收益只存在于走 WebView 的页面；代码里的真机证据是
视频站（播放规则 needsWebView、Cloudflare 挑战闸门）与漫画阅读页（manmanapp 懒加载图片），书站都是服务端渲染。
选择器在**列表、详情、剧集**这类一次渲染出固定数量条目的页面语义安全；在漫画阅读页危险（图片分批追加，
300 ms 空档就会在 30 张时返回、少看 20 页）；对视频播放页不适用（无数量信号）。

关键发现：规则模型里**已有 `ready: ExtractRule?` 字段**（漫画 V2 列表/详情、视频列表/详情/剧集、旧版 SiteRule），
正规化合同把它列入白名单（`item`、`ready` 用 `function="raw"`），但 Core 与 Runtime 从未消费它。因此接线不按 kind
硬填条目选择器，而是**消费这个已声明的字段**：`Runtime/Common/ReadinessSelector.swift` 只放行 CSS 选择器
（缺省 kind 即 css；`this` / `&` / `$` 与 XPath、JSON 路径一律回 nil），接到漫画列表/详情、视频列表（含搜索）/详情/剧集
五个加载点；阅读页、播放页、书、以及所有 API（JSON）路径不接。今天线上规则的 `ready` 全为空，
**接线本身对所有现有规则零变化**；收益在规则作者给某条规则显式写上 `ready` 后逐条出现，影视线不写就完全不动。

验证：Runtime 包测试 10 例（新增 `ReadinessSelectorTests` 4 例）通过；App 与测试目标 0 警告；闸门干净。

**模拟器验证整链（同日第三步，iPhone 17 Pro 模拟器）**。5.5 前半的测量只驱动 `WKWebViewDOMStabilityWaiter`，
没有经过真正的加载器；接线又只有 Runtime 单测。这一步补上两段，合起来就是「规则 `ready` → 加载器提前返回」整链：

| 用例 | 驱动的真实对象 | 结果 |
|---|---|---|
| `WKWebViewHTMLLoaderReadinessTests`：静态 3 条列表 | `WKWebViewHTMLLoader(.baseline).loadRenderedContent`，`data:` URL、`needsWebView` 请求 | 不声明 2,416 ms → 声明 `.item` **1,139 ms**（两轮均复现：2,358 → 1,132） |
| 同上：800 ms 后才写入 3 条 | 同上 | 2,100 ms 返回，返回的 HTML 里 `<ul id="list">` 内恰有 3 条 |
| `ComicListReadinessSelectorWiringTests`：3 例 | `ComicSourceListLoader` + `CoreComicRuleSourceParser`，记录型页面加载器截住 `PageLoadRequest` | 声明 `ready: .card` → 请求带 `.card`；不声明 → `nil`；声明 `this` → `nil` |

两点值得记下：加载器整链的绝对耗时比只驱动 waiter 高约 800 ms（WebView 创建、cookie 同步与导航），
这是加载器固定成本，与就绪选择器无关，节省量（约 1.2 s）与 waiter 层测得的一致。
其二，漫画 V2 严格校验在更上游就拒绝 XPath 的 `ready`（`comic-v2-extract-xpath-*`），
所以接线层「非 CSS 回 nil」这一档在漫画路径上永远到不了，只由 Runtime 单测覆盖；接线层测试改测校验放行、
但对整页无意义的当前节点标记。首轮用例把 `<script>` 源码里的字面量也数了进去（得 6 而非 3），已改为只数渲染出的 `<ul>` 内容。

**真实站点联网测量（同日第四步）**。前三步都跑在固定输入上（`data:` URL 与记录型加载器）。
这一步用线上来源 `manga18-club--list-manga`（manga18.club）的**真实规则 JSON**，经真实严格校验器解析、
真实 `DefaultPageLoader`（`.baseline` 策略）打真实网络，只在「声明与不声明 `ready`」之间对比，其余逐字相同。
该站列表原本 `needsWebView: false`，为测量机制本身把列表的 `request` 改成 `needsWebView: true`、
`scope: "rule"`（规则级请求必须声明 `scope: rule`，否则严格校验器直接拒绝，路径 `$.ruleSets.listRules[0].request.scope`）。

| 轮次 | 不声明 `ready` | 声明 `ready: .col-xs-6` | 解析出的条目数 |
|---|---|---|---|
| 第一轮 | 5,016 ms | **2,509 ms** | 两者都是 20 |
| 第二轮 | 5,533 ms | **1,904 ms** | 两者都是 20 |

模拟器统一日志里捕获到的判定原因，是这条链路最直接的证据：

```
dom-stability reason=exhaustedChecks waitedMs=3438 checks=12 selector=none     matched=-  url=.../list-manga/1
dom-stability reason=selectorReady   waitedMs=314  checks=2  selector=declared matched=20 url=.../list-manga/1
```

不声明时走满 12 轮、等 3,438 ms；声明后第 2 轮即返回、等 314 ms，且 `matched=20` 与随后解析出的条目数一致——
**等待时间降到约十分之一，内容一条不少**。两轮端到端耗时都减半以上。

一个附带发现：这条线上规则里**唯一 `needsWebView: true` 的位置是阅读页（gallery）**，
而阅读页正是我们判定为不安全、故意没有接线的一档（图片分批追加）。所以这条规则在不改 `needsWebView` 的前提下，
没有可以安全声明 `ready` 的位置。要在真机上看到收益，需要一条列表或详情本身就走 WebView 的规则。

**线上规则盘点（同日第五步，最重要的一条）**。原以为「给规则写 `ready`」是一件待办的服务端工作。
实际盘完 fwq 侧的目录规则后结论相反：**多条线上规则早就声明了 `ready`，只是 App 从不消费**。

| 线上来源 | kind | 列表的 `ready` | App 请求实际携带 |
|---|---|---|---|
| yifan-tv（爱壹帆） | video | `#list-page > .v-c` | 一致 |
| jable-tv | video | `.pb-3 > .row > .col-6` | 一致 |
| kinogomy-net | video | `.lcomm` | 一致 |

核对方式：把 fwq 仓库里这三站的明文 `ruleJSON` 包成 App 的 `SourceConfiguration`，经 App 自己的解码、
`ResolvedVideoSiteRule` 校验与真实 `VideoSourceListLoader`，用记录型页面加载器截住 `PageLoadRequest`。
三站的列表与详情 `ready` 都是 `selectorKind: "css"`，本次接线全部采纳；剧集的 `ready` 是
`selectorKind: "current"`，接线按设计拒绝（当前节点对整页没有意义）——**声明的两种形态都落在预期行为上**。

因此这三条**不需要任何服务端改动**，收益随 App 这次发版自动出现。

还缺 `ready` 的两条，是真正需要服务端补的：

| 线上来源 | kind | 缺口 | 该写的值 |
|---|---|---|---|
| patternrecognition-cn（178漫画网） | comic | 列表与详情都走 WebView（`sharedRequest.needsWebView: true`），无 `ready` | 列表可用其条目选择器 `.mh-list > li > .mh-item` |
| 91porn-com | video | 详情 `needsWebView: true`，无 `ready` | 待按该层实际条目定 |

补这两条要走 fwq 的正规化闸门与发布通道（video 走 `publish-video-catalog`，comic 走生成器发布），
按 fwq 的 `AGENTS.md`「Catalog Source 发布默认关闭」，每次发布都需要显式授权。

**一条不能做的事**：本节第四步那份强制 `needsWebView: true` 的 manga18.club 规则是**测量用的人工制品**，
不可发布。该站列表走普通 HTTP 只要 0.21 s，改走 WebView 即使声明了 `ready` 也要 1.9–2.5 s，
发上去等于让该来源慢 9 到 12 倍。`ready` 只在该层**本来就必须走 WebView** 时才有意义。

**剩余两件都不在 App 侧**：(1) 挑一两条已知要 WebView 的规则写上 `ready`（同一选择器写 `item` 与 `ready` 即可），
真机看日志 `dom-stability reason=selectorReady` 与耗时——影视线的必须真机；(2) 「`ready` = WebView 就绪选择器」
这一语义补进正规化合同，按你的决定放到 fwq 侧立项完成后同步到服务器版本，本次不改合同文件。

## 5.5.1 就绪选择器该取什么值（2026-09-18）：判据由测量定死

5.5 把机制与接线做完后，剩下的问题是「规则里的 `ready` 该写什么」。这不是风格问题——**取错会丢内容**。

**真实站点分不出胜负**。178 的详情页（`sharedRequest.needsWebView: true`），同一条真实规则的五个变体
只差 `detail.ready`，打同一个真实详情页：不声明 9,457 ms、信息块 4,831 ms、章节容器 4,840 ms、
章节项 4,434 ms、弱值 `ul` 4,776 ms——**抽出的章节数全是 549**。该站章节在初始 HTML 里就有，测不出差别。

**固定输入把风险问了出来**。页面先有 3 个导航 `<ul>`，1,300 ms 后才追加装 20 条章节的第 4 个 `<ul>`
（注入时刻选在加载器地板约 1.1 s 之后、历史机制 12 轮上限约 2.4 s 之前，三种取法才分得开）：

| 取法 | 耗时 | 抽出的章节数 |
|---|---|---|
| 宽选择器 `ul` | 1,112 ms | **0 —— 丢内容** |
| 内容选择器 `.chapters li` | 2,092 ms | 20 |
| 不声明（历史机制） | 2,960 ms | 20 |

**判据**：`ready` 必须命中**要提取的内容本身**，不能是内容到达前就存在的容器。取对了既不丢内容，
又比历史机制快约 0.9 秒。这条同时解释了为什么 list 层一直是对的——模型答的本就是 item 选择器。

同日一并量到的边界：**内容若晚于历史机制的 12 轮上限才到，三种取法都丢**。那是既有上限（见 5.1），
不是就绪选择器引入的问题。

**新增常驻闸门** `BrowseCraftTests/Infrastructure/Network/ReadinessSelectorContentSemanticsTests.swift` 3 例，
把上表三行钉住。规则生成侧据此立了两条条款：fwq `BC-COMIC-131`（list 交付模型已作答的 `ready`，
三站复扫显示它等于 item 选择器）与 `BC-COMIC-132`（detail 的 `ready` 取 `chapterRule.item` 本身，
不取模型答的容器）。

## 5.6 Swift 6 语言模式（2026-09-18）：把「警告为零」固化成编译错误

阶段 1 清零 37 条编译器警告、阶段 0 给四个包补上 complete 严格并发之后，剩下的风险不是「现在有问题」，
而是**这个状态只靠警告维持**——下一个人加一处非 Sendable 的共享可变状态，最多得到一条警告，
而警告不会让任何构建失败。切到 Swift 6 语言模式后这类问题直接是编译错误。

**先量代价，再决定**（零成本固定输入，改动当时已还原）：

| 目标 | Swift 6 语言模式下 |
|---|---|
| 四个包（`swift build -Xswiftc -swift-version -Xswiftc 6`） | 各 0 错误 |
| App 与测试目标（`SWIFT_VERSION=6.0` 写在工程设置里） | 0 错误、0 编译器警告 |

中途用命令行把设置压到所有依赖上时，第三方的 Fuzi 报 2 条错（`xmlFree`、`XPathNodeSet` 的全局可变状态）。
那是命令行写法的问题：按工程设置写只作用于自己的目标，SwiftPM 依赖各自按自己的 tools-version 编译。

**实施**：四个包的 `swift-tools-version` 由 5.9 提到 6.0，`swiftSettings` 由
`.enableExperimentalFeature("StrictConcurrency")` 换成**显式**的 `.swiftLanguageMode(.v6)`
（tools-version 6.0 的默认语言模式本就是 v6，但隐含默认改了没人看得出来，所以显式声明一次）；
工程 `SWIFT_VERSION` 由 5.0 改为 6.0。

**真实切换只暴露一处**，在测试代码里：`VideoSiteRulePlaybackValidationTests` 的
`static let iframeWebUIRule: [String: Any]` 被判为可共享可变状态（`[String: Any]` 不是 Sendable）。
它本身是只读夹具，改为计算属性即无共享状态，取值逐字不变。产品代码一处没改。

**验证**：Core 228 例（4 例按设计跳过）、Domain 5 例、Runtime 10 例、APIKit 33 例全部通过；
App 499 例 Swift Testing + 62 例 XCTest 通过，编译错误 0、编译器警告 0。

**新增闸门**（`scripts/check-architecture-boundaries.sh`，随每次构建跑）：工程的 `SWIFT_VERSION` 必须是 6.0，
四个包必须各自声明 `swift-tools-version: 6.0` 与显式的 `.swiftLanguageMode(.v6)`。
用三种反证验过：把工程调回 5.0、拆掉某个包的显式声明、把某个包的 tools-version 调回 5.9，都被挡住。
闸门要的是**显式声明**而不是隐含默认，理由与上面同一条。

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
