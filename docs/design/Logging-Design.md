# 日志设计

本文是全仓日志的唯一定义点：App 与五个兄弟包（BrowseCraftLog、BrowseCraftCore、BrowseCraftDomain、BrowseCraftRuntime、
BrowseCraftAPIKit）怎么记日志、记成什么形状、怎么脱敏、写到哪、哪些地方必须有记录。设计的讨论与裁定过程见 Claude 文档
「BrowseCraft 统一日志方案设计」（https://claude.ai/artifact/PGu1HEr4yyLCqozdfuqFi1）。

日志与埋点、崩溃诊断分工不同：Analytics 统计用户行为，Crashlytics 收崩溃与非致命错误（[Analytics-Events-Design.md](Analytics-Events-Design.md)），
日志是排查用的完整过程记录。三者可以出现在同一个调用点，互不替代。

上报链路：调用点 → `AppLog`（BrowseCraftLog 包）→ 已安装的出口。包只负责收下记录、交给出口，不依赖 OSLog 与 Firebase；
App 启动时由组合根安装三个出口：OSLog、本机滚动文件、Crashlytics 日志行。

## 1. 条款

- `BCA-OBS-010` 全仓只有一个日志类型 `AppLog`，定义在 BrowseCraftLog 包。App 与五个包的源码不得出现 `print`、`debugPrint`、
  `NSLog`、`os_log`；`import OSLog` 与 `Logger(` 只许出现在 App 的日志后端文件 `BrowseCraft/Shared/Logging/OSLogSink.swift`。
  `scripts/check-architecture-boundaries.sh` 执行。
- `BCA-OBS-011` 每条记录 = 级别 + 类别 + 事件名 + 字段。事件名是小写短横线串（`request-finished`），字段的值只能是 `LogValue`，
  不接受裸字符串；值属于哪一类由调用点在类型上声明，脱敏随类型自动发生（第 4 节）。
- `BCA-OBS-012` 日志不得出现 Cookie、token、授权头、密钥、网址查询串与片段、账号与设备标识的明文。作品标题、搜索词、章节名、
  网址路径只在 Debug 构建留明文，Release 构建记长度或哈希。新的值类型先改第 4 节再改代码。
- `BCA-OBS-013` `debug` 级只在 Debug 构建生效，Release 下字段不求值；`info` 及以上在 Release 构建写 OSLog 与本机文件，
  `notice` 及以上另写 Crashlytics 日志行（`BCA-OBS-017`）。
- `BCA-OBS-014` 页面、启动、生命周期、规则请求、PortalCore 请求、图片、规则执行、数据库这八条链路在各自唯一的入口记录（第 7 节），
  新加的页面、请求与规则阶段因此自动有记录，业务代码不得为它们另写同类记录。
- `BCA-OBS-015` 被捕获后不再抛出、也没有变成返回给调用方的失败值（结果枚举、校验问题、失败计数）的错误，必须记一条 `error`，
  或在 `catch` 处写明为什么不记（用户取消、被新请求取代、预期内的「不存在」）。只改了界面文案就算吞掉，要记。
  `try?` 只许收敛：现存的登记在 `scripts/try-optional-baseline.txt`，新增的 `try?` 要么改 `do/catch`，要么在同一行写
  `// try?: <理由>` 说明丢掉错误是有意的。`scripts/check-architecture-boundaries.sh` 执行。
- `BCA-OBS-016` 本机日志文件只记 `info` 及以上，放在 Caches/Logs，两个文件轮换、合计不超过 10 MB；设置页「导出诊断日志」只在 Debug 构建出现、用系统分享面板发出，TestFlight 与商店包不显示（用户 2026-10-21 裁定；线上问题靠页内问题报告带的日志片段）。
  删除账号时一并删除本机日志文件。日志文件不进 iCloud 备份，也不随云同步上传。
- `BCA-OBS-017` Crashlytics 日志行只写 `notice` 及以上记录的类别与事件名，不带字段；崩溃诊断开关关闭时不写（`BCA-OBS-006`）。
  页面轨迹的 `screen=` 行仍由 `CrashDiagnostics.setScreen` 写（[Analytics-Events-Design.md](Analytics-Events-Design.md) 第 6.2 节）。

## 2. 记录形状

```swift
AppLog.notice(.network, "request-finished", [
    "host": .host(url),
    "path": .path(url),
    "status": .int(response.statusCode),
    "ms": .duration(elapsed)
])
AppLog.error(.database, "favorite-write-failed", ["error": .error(error)])
AppLog.debug(.rule, "page-image-resolved", ["index": .int(index), "title": .content(title)])
```

每条记录由 `AppLog` 生成记录时补上时间、是否主线程与当前页面；上下文里的会话 ID 与 Crashlytics 的 `sessionId` 键同值，两边对得上。

## 3. 级别

| 级别 | 用于 | Debug 构建 | Release 构建 |
| --- | --- | --- | --- |
| `debug` | 逐页、逐张图、选择器命中这类高频调试点 | 全部出口 | 不求值、不输出 |
| `info` | 页面进入、请求完成、规则阶段完成、前后台切换 | 全部出口 | OSLog 与本机文件 |
| `notice` | 账号、购买、同步、来源增删等关键状态变化 | 全部出口 | OSLog、本机文件与 Crashlytics 日志行 |
| `error` | 任何被捕获、用户看得到或会影响结果的失败 | 全部出口 | 同 notice |
| `fault` | 不该发生的状态，不变量被打破 | 全部出口 | 同 notice |

## 4. 字段类型

| `LogValue` | 写进日志的样子 |
| --- | --- |
| `int` / `bool` / `duration` / `bytes` | 原值；时长记毫秒，空间记字节 |
| `enumValue` | 枚举的原始值 |
| `code` | 有限取值的机器码（状态、原因、服务端错误码、阶段名），原样记录、最长 80 字符；调用点保证它不是用户内容、网址或标识 |
| `host` | 只留主机名 |
| `path` | Debug 构建为去掉认证、查询串与片段后的明文；Release 构建为主机名明文加路径的 SHA-256 前 8 位十六进制（`host#xxxxxxxx`） |
| `id` | SHA-256 前 8 位十六进制，用于来源 ID、账号、交易号、实体 ID |
| `content` | Debug 构建明文；Release 构建只记长度 |
| `error` | `ErrorDiagnostics.summary` 的输出：类型名、domain:code、错误自己声明的摘要 |
| `text` | 只在 `debug` 级出现，过一遍 `AppLog.sanitizedDebugMessage`；`check-architecture-boundaries.sh` 按括号配平找出 `AppLog.info` / `notice` / `error` / `fault` 调用里的 `.text(` 并判失败 |

没有「原样字符串」这一类：要记一个值，先决定它属于哪一类。

## 5. 类别

类别即 OSLog 的 category，控制台里按它过滤。`LogCategory` 的每个 case 带 `///` 中文注释并在下表登记，闸门 A13 双向核对。

| 类别 | 链路 |
| --- | --- |
| `app` | 不属于下列任何链路的 App 级记录 |
| `startup` | 启动装配与开屏 |
| `lifecycle` | 前后台切换与内存警告 |
| `screen` | 页面曝光 |
| `network` | 规则请求、网页加载、预检加载与有声书音频请求 |
| `portal` | PortalCore 接口请求 |
| `image` | 封面、缩略图与漫画页加载 |
| `rule` | 规则执行各阶段与规则目录 |
| `parse` | Core 的解析、正规化与校验 |
| `database` | 数据库打开、迁移与读写 |
| `sync` | iCloud 同步与续看位置同步 |
| `identity` | 登录、退出、身份切换与删除账号 |
| `purchase` | 内购、恢复购买与权益 |
| `coin` | coin 余额与激励广告到账 |
| `ad` | 广告 SDK 与激励广告 |
| `push` | 推送注册与到达 |
| `cache` | 图片与网页缓存 |
| `playback` | 视频与有声书播放 |
| `reader` | 漫画与书阅读器 |
| `generation` | 规则生成与预检 |
| `credential` | 站点登录凭据 |
| `security` | 内容锁定与钥匙串 |
| `diagnostics` | 日志与诊断自身（出口安装、日志导出） |

## 6. 出口

| 出口 | 实现 | 内容 |
| --- | --- | --- |
| OSLog | `OSLogSink`，全仓唯一一处 `Logger(` | 全部级别；字段已脱敏，统一标 `privacy: .public` |
| 本机滚动文件 | `LogFileSink`，Caches/Logs 下 `browsecraft-0.log` 与 `browsecraft-1.log`，每行一条 JSON | `info` 及以上；单个文件到 5 MB 时轮换 |
| Crashlytics 日志行 | `CrashlyticsLogSink`，经 `CrashDiagnostics.logLine` 写 | `notice` 及以上的类别与事件名 |

出口在后台串行队列里写，调用方不等待。出口在组合根装配时安装，早于 Firebase 配置；Crashlytics 出口在 `CrashDiagnostics.configure`
之后才安装。测试用 `InMemoryLogSink` 收集记录做断言。

## 7. 公共钩子

| 链路 | 入口 | 记什么 | 级别 |
| --- | --- | --- | --- |
| 启动 | `AppBootstrapState`、AppDelegate 与 `AppLogging.installBaseSinks` | 出口装好、Firebase 配置完成、每一步的耗时（数据库与身份、容器）、失败在哪一步 | info / error |
| 生命周期 | 根视图的 scenePhase（`AppLogging.logScenePhase`）与 AppDelegate 的内存警告 | 进前台、进后台、内存警告 | info / notice |
| 页面 | `AnalyticsScreenReporter` 经 `AppLogging.logScreenShown` | 每次页面曝光，含关掉 sheet 后的补报；同时更新记录上下文里的当前页面 | info |
| 规则请求 | `AlamofireHTTPClient`、`WKWebViewHTMLLoader`、两个预检加载器、`SiteBookAudioHTTPClient` | 方法、主机、路径、状态码、耗时、字节数 | info / error |
| PortalCore 请求 | `PortalAPIClient.sendData`（APIKit） | 方法、路径模板（标识段换成 `:id`）、耗时、状态码与服务端错误码；不记请求体、查询串与 token | info / error |
| 图片 | `ImagePipelineFailureLogger`（共享管线与缩略图管线） | 加载失败的主机与错误 | error |
| 规则执行 | `RuntimeStageLog.measure`（三个来源运行时的每个公开入口）与 `RuleFailureDiagnostics.report` | 阶段开始、完成与耗时，失败分类与失败点 | info / error |
| 数据库 | `AppDatabase` 的打开流程与迁移器 | 每个迁移的名字、打开与迁移失败 | notice / error |

## 8. 业务代码必须自己打的点

- 被吞掉的错误（`BCA-OBS-015`），记 `error`。
- 关键状态变化，记 `notice`：登录与退出、身份切换、删除账号各步、购买与恢复的每一步、权益变化、云同步一轮的开始与结果、
  来源增删与启用、规则目录更新、规则生成提交与推送到达、激励广告结局与到账轮询、内容锁定与解锁。
- 播放与阅读器状态，记 `info`：打开、换章或换集、播放器状态变化（缓冲、就绪、失败）、关闭；翻页与拖动进度不记。
- 用户点了什么由 Analytics 负责，日志只记操作引起的状态变化与结果。
