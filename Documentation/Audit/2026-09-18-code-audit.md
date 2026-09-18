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
- **F2-11 判定不动**：占位图像素尺寸（视频详情 @3x 1320×1386、漫画列表 @3x 600×900）接近其最大显示分辨率，缩小收益小；两段 mp4（6.5 MB、5.9 MB）转 HEVC 是视觉资产取舍，由你决定，建议目标：HEVC 同码率下体积约减半。
- **F2-7 待专项**：触及影视线共用默认值，按既定要求需固定站点集合测量与真机复核后单独实施；机制设计已定（MutationObserver 静默窗口 + 按请求声明的窗口时长，当前 500 ms + 6×300 ms 作基线）。
- 验证：Core/Runtime 构建、Core 测试目标编译、App 与测试目标构建均通过、0 警告，边界闸门干净。模拟器（iPhone 17 Pro，iOS 26.5）冒烟：正常签名的 Debug 包引导成功、启动动画播放、进程稳定；用 `CODE_SIGNING_ALLOWED=NO` 构建的包会在引导阶段以 `KeychainAppUserIdentityStoreError` 失败（无 application-identifier 时 Keychain 写入被拒），属于构建方式问题、不是代码回归——顺带发现引导失败页只把错误类型名哈希成诊断码、底层 OSStatus 没有进任何日志，列为后续项。**待真机复核：规则生成的发现分析结果与改前一致（同一页候选集合相同）、清空历史。**

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
