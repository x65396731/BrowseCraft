# 页内问题报告

设计文档（含两个入口、报告面板与数据流三张图）：[BrowseCraft 页内问题报告入口设计书](https://claude.ai/artifact/R1jd8HR8q6hKoSKh1vTjMB)。
设计与实施状态见 [STATUS.md](../STATUS.md)。面板版式沿用网址输入页的重新生成面板，颜色只取规则目录的色板
（[网址输入页](Generation-Input-Page-Redesign-Design.md)、[规则目录](Catalog-Page-Redesign-Design.md)），App 内不新增色值。

## 一、范围

每个显示规则执行结果的页面有一个同一形态的「报告问题」入口。用户点「发送」后，App 把「哪条规则、哪一版、在哪个阶段、
对哪一页、出了什么错」打包发给 PortalCore，换回一个报告编号；开发者按编号、诊断码或来源与规则版本查询。

不在本文范围：客服对话与处理进度回执（第一、二期只回编号）、截图、自动上报、给报告发 coin、规则执行本身与现有埋点和
Crashlytics 的采集范围。邮件方案（面板把报告与日志打成文件、走系统分享面板）只作服务端不可用时的兜底。

## 二、条款

- `BCA-OBS-018` 问题报告只在用户点面板上的「发送」时离开设备。App 不得自动、定时或在后台发送报告，发送失败也不得
  自动重试，只给「再试一次」。「发送使用统计」与「发送崩溃诊断」两个开关不管报告，与导出诊断日志同一原则（`BCA-OBS-016`）；
  面板自身的埋点仍受使用统计开关管（`BCA-OBS-005`）。
- `BCA-OBS-019` 报告只发第六节登记的字段。任何情况下不得发送：Cookie、站点登录凭据、授权头、令牌、网址查询串与片段、
  网页源码片段、规则错误的 `errorDescription` 原文（它内嵌完整网址）、设备标识与 Apple 账号标识。对象网址只留 scheme、
  主机与路径，路径按第六节的规则遮蔽令牌段；App 与 PortalCore 用同一套规则各清洗一遍。作品与章节标题、网址路径与搜索词
  只出现在报告里，不得因此写进日志、埋点或 Crashlytics（`BCA-OBS-002`、`BCA-OBS-008` 不变）。
- `BCA-OBS-020` 失败快照只由 `RuleFailureDiagnostics.report` 在上报之后写入，只在内存里、不落盘，被挡掉的取消不进快照。
  各页不得自行收集或保存失败快照，面板按（失败点，来源 ID）向快照存储取（`BCA-OBS-007` 的单一入口不变）。
- `BCA-OBS-021` 问题类型是第五节的封闭枚举：页面只显示该页登记的选项，「其他」总在最后，每页不超过 9 个。
  新增、改名或改归属先改本文再改代码；服务端按问题码统计，显示文字按内容类型换词、问题码不变。
- `BCA-OBS-022` 报告里的规则版本取 `sources` 表的 `catalogRevision`，即规则目录下发的服务端指纹 `catalogSHA256`。
  本机的 `catalogRuleFingerprint` 只用于判断目录规则是否变化、决定是否跟随更新，不得作为对外的规则版本标识上报：
  它是 App 对重新编码的规则原文算的值，与服务端指纹不同。
- `BCA-UI-006` 第三节表中的页面各有两个入口，打开同一个报告面板：失败态上的「报告问题」小字链接，以及页面「…」菜单里的
  「报告这一页的问题」。失败态入口不得做成与「重试」「登录」同级的按钮；受限态（要登录）是预期状态，不加入口。

## 三、覆盖页面与入口

入口跟着「这一页显示的是哪一步规则的结果」走。`scope` 是报告对象的枚举，取值固定为下表第二列。

| 页面（`DiagnosticScreen`） | scope | 对应失败点 | 失败态入口加在哪 | 「…」放在哪 | 期 |
| --- | --- | --- | --- | --- | --- |
| `library` 库页 | list（列表、当前分类、翻页） | `library_refresh`、`library_pagination` | `LibraryStateBanner` 的失败态、`LibraryPlaceholderView`、`LibraryPaginationFooterView` 的失败文案后 | 页头圆按钮行，搜索与账号圆按钮旁 | 一 |
| `library_search` 来源内搜索 | search | `library_search`、`library_search_pagination` | `LibraryStateBanner` 的失败态 | 结果眉行右侧 | 一 |
| `comic_detail` 漫画详情 | detail（详情与章节目录） | `comic_detail` | 横幅失败态、空目录占位 | `DetailTopButtons` 第三个圆按钮 | 一 |
| `video_detail` 影视详情 | detail（详情、选集、某一集解析） | `video_detail`、`video_episode_resolve` | 横幅失败态、空目录占位 | 页头圆按钮行 | 一 |
| `book_detail` 站点书详情 | detail（详情与目录） | `book_detail` | `LibraryStateBanner` 的失败态 | `DetailTopButtons` | 一 |
| `comic_reader` 漫画阅读器 | chapter（当前章节） | `comic_reader`；单页图片失败不报 | 失败弹窗加一个按钮 | 导航栏右侧 | 一 |
| `book_reader` 书阅读器 | chapter | `book_reader_open`、`book_reader_chapter`（第八节） | 打开失败的 `EmptyStateView`、单章失败说明页 | 导航栏右侧，目录与书签旁 | 一 |
| `audiobook_player` 有声书 | chapter | `book_reader_open` | 同书阅读器 | 同书阅读器 | 二 |
| `video_player` 视频播放器 | episode（当前一集与线路） | `video_playback`；播放层失败走 `playback_failed` | 失败弹窗加一个按钮 | 网页播放器工具条、原生播放器覆盖层 | 二 |
| `sources` 来源页 | source_list（首次拉列表与刷新） | `source_select_refresh`、`source_refresh` | 失败弹窗加一个按钮 | 来源行的长按菜单 | 二 |
| `catalog` 规则目录 | catalog_add（添加来源失败） | 不经 `RuleFailureDiagnostics` | 失败行上的文字链接 | 无 | 二 |

临时资源详情与播放器（`temporary_detail`、`temporary_player`）不是规则直接产出，来源调试页 `source_debug` 本就是只读的规则查看页，
都不放入口。

- 失败态入口：`LibraryStateBanner` 加可选的报告动作，在说明句下多一行动作蓝小字「报告问题」，右侧「登录」「重试」不动；
  空列表占位与 `EmptyStateView` 放在重试按钮下；失败弹窗关掉后再拉起面板。
- 常驻入口：一个与旁边收藏、搜索、账号同样式的「…」圆按钮或工具栏项，点开是系统菜单，其中一项「报告这一页的问题」
  （图标 exclamationmark.bubble）。以后的「分享」「用浏览器打开」也放这个菜单。

## 四、报告面板

底部面板，中号高度、可拉到大号，版式同 `RegenerateRuleSheet`，颜色只取 `CatalogPalette`。从失败态进来时预选第一个问题类型、
对象卡下写出当时的失败文案；从「…」进来不预选、没有警示行。

| 块 | 内容 |
| --- | --- |
| 顶部 | 抓手；28pt 动作蓝图标圆 + 标题「报告问题」；一句「会把下面的信息发给开发者，用来查这条规则。」 |
| 对象行 | 小卡：类型色图标 + 来源名 · 页面名（如「笔趣阁 · 第 12 章」）；从失败态进来时卡下一行警示色小字写当时的失败文案 |
| 站点侧提示 | 失败快照属于网络失败、反爬页、HTTP 429 / 5xx 或需要账号时，问题类型上方一行灰字「看起来是网站暂时打不开或要登录，不一定是规则的问题；仍然可以报告。」不拦发送 |
| 问题类型 | 单选芯片，按第五节给该页的选项 |
| 补充说明 | 可选文本框，占位「例如：第 3 页之后都是同一张图」，最多 500 字 |
| 将发送的信息 | 默认收起的一行「将一并发送：页面、规则版本、失败信息、最近 10 分钟的诊断日志」，展开逐项列出第六节的字段与取值（网址为清洗后的值）；日志一项带开关，默认开 |
| 主按钮 | 蓝色胶囊「发送」，发送中转圈；不扣 coin，不用滑动确认 |
| 结果 | 成功：面板换成 `StatusCardView`（蓝 ✓）「已发送」+ 报告编号（形如 R-7KQ2-M9XA，点一下复制）+「联系我们时报这个编号」，下方「完成」。失败：警示色小字 +「再试一次」，已填内容不丢；服务端回限流时写「发得太频繁了，稍后再试」 |

## 五、问题类型

每页的选项（显示文字按类型换词：集 / 话 / 章；库页的「最新」指封面下的最新一集 / 话 / 章）：

| 页面 | 影视 | 漫画 | 书（含有声书） |
| --- | --- | --- | --- |
| 库页 | 加载失败 · 列表是空的 · 封面不显示 · 标题不对 · 「最新」不对 · 分类不对 · 翻页出错 · 乱码 · 其他 | 同左 | 同左 |
| 来源内搜索 | 搜索失败 · 搜不到 · 结果对不上 · 标题不对 · 只有第一页 · 其他 | 同左 | 同左 |
| 详情与目录 | 加载失败 · 没有剧集 · 集数不全 · 线路混在一起 · 顺序不对 · 简介或信息不对 · 封面不显示 · 其他 | 加载失败 · 没有章节 · 章节不全 · 顺序乱或重复 · 付费章节没标出 · 简介或信息不对 · 封面不显示 · 其他 | 加载失败 · 目录是空的 · 目录不全 · 顺序乱或重复 · 章节名乱码 · 简介或信息不对 · 封面不显示 · 其他 |
| 阅读与播放 | 播不出来 · 不是这一集 · 广告或跳转 · 打开的是网页 · 一直在加载 · 换线路也不行 · 登录后仍看不了 · 其他 | 打不开 · 一页都没有 · 图片加载不出 · 少页 · 顺序乱或重复 · 混进别的图 · 登录后仍看不了 · 加载很慢 · 其他 | 书阅读器：打不开 · 空白或只有标题 · 少了段落 · 只有一部分 · 夹着广告或杂字 · 乱码 · 不是这一章 · 其他。有声书：播不出来 · 不是这一章 · 时长或进度不对 · 登录后仍听不了 · 其他 |

问题码（`problem_type` 的取值）：

| 问题码 | 显示文字 | 用在 |
| --- | --- | --- |
| `load_failed` | 加载失败 / 搜索失败 / 打不开 | 除播放器外各页 |
| `playback_failed` | 播不出来 | 影视播放器、有声书 |
| `list_empty` | 列表是空的 | 库页 |
| `cover_missing` | 封面不显示 | 库页、详情 |
| `title_wrong` | 标题不对 | 库页、搜索 |
| `latest_wrong` | 「最新」不对 | 库页 |
| `category_wrong` | 分类不对 | 库页 |
| `pagination_wrong` | 翻页出错 / 只有第一页 | 库页、搜索 |
| `garbled_text` | 乱码 / 章节名乱码 | 库页、书详情、书阅读器 |
| `no_results` | 搜不到 | 搜索 |
| `results_irrelevant` | 结果对不上 | 搜索 |
| `toc_empty` | 没有剧集 / 没有章节 / 目录是空的 | 三种详情 |
| `toc_incomplete` | 集数不全 / 章节不全 / 目录不全 | 三种详情 |
| `lines_mixed` | 线路混在一起 | 影视详情 |
| `order_wrong` | 顺序不对 / 顺序乱或重复 | 三种详情、漫画阅读器 |
| `lock_unmarked` | 付费章节没标出 | 漫画详情 |
| `info_wrong` | 简介或信息不对 | 三种详情 |
| `wrong_item` | 不是这一集 / 不是这一章 | 影视播放器、书阅读器、有声书 |
| `ads_or_redirect` | 广告或跳转 | 影视播放器 |
| `web_fallback` | 打开的是网页 | 影视播放器 |
| `stuck_loading` | 一直在加载 | 影视播放器 |
| `all_lines_failed` | 换线路也不行 | 影视播放器 |
| `paywall_after_login` | 登录后仍看不了 / 仍听不了 | 影视播放器、漫画阅读器、有声书 |
| `content_empty` | 一页都没有 / 空白或只有标题 | 两种阅读器 |
| `images_not_loading` | 图片加载不出 | 漫画阅读器 |
| `content_missing` | 少页 / 少了段落 | 两种阅读器 |
| `non_content_images` | 混进别的图 | 漫画阅读器 |
| `slow` | 加载很慢 | 漫画阅读器 |
| `chapter_partial` | 只有一部分 | 书阅读器 |
| `junk_text` | 夹着广告或杂字 | 书阅读器 |
| `progress_wrong` | 时长或进度不对 | 有声书 |
| `other` | 其他 | 各页 |

- 从失败态进来时预选第一个（加载失败 / 搜索失败 / 打不开 / 播不出来），从「…」进来不预选。
- 不设「需要登录」一项：受限是预期状态，横幅已给「登录」；登录之后还不行才报，用 `paywall_after_login`。
- 上线后「其他」占比超过 20% 时，按补充说明里的高频词补新码（`BCA-OBS-021`）。

## 六、报告内容与边界

| 组 | 字段 | 取值与来源 |
| --- | --- | --- |
| 报告 | `clientReportId` | App 生成的 UUID；服务端按它去重，重试得到同一个报告编号 |
| 报告 | `entry` | failure_state（失败态入口）或 page_menu（常驻入口） |
| 报告 | `scope`、`problemType` | 第三、五节的枚举 |
| 报告 | `note` | 补充说明，可空，最多 500 字 |
| 环境 | `appVersion`、`buildNumber`、`systemVersion`、`deviceModel`、`locale` | 与 Crashlytics 全局键同源 |
| 身份 | `diagnosticCode`、`sessionId` | 诊断身份；账号不在报文里，已登录时服务端从令牌取 |
| 页面 | `screen` | `DiagnosticScreen` 原始值 |
| 来源与规则 | `sourceId`、`sourceKind`、`sourceOrigin`、`ruleRevision`、`ruleAppliedAt` | 目录 ID（明文，服务端按它查规则）、类型、公共或个人生成；`ruleRevision` 取 `catalogRevision`，可空；`ruleAppliedAt` 取来源的更新时间（`BCA-OBS-022`） |
| 对象 | `targetURL` | 当前列表页、详情页、章节页或剧集页的网址，按下文清洗 |
| 对象 | `targetTitle`、`chapterTitle`、`chapterIndex`、`pageIndex` | 作品名、章节名、第几章、第几页 |
| 对象 | `categoryKey`、`searchKeyword` | 库页分类键；搜索词只在搜索页的报告里带 |
| 失败快照 | `failure` | 失败点、阶段、类别、错误 case 名、状态码、ruleID、operation、选择器、脱敏摘要、发生时间，取自 `RuleExecutionError` 的 case 与关联值；常驻入口且最近没有失败时为空 |
| 日志片段 | `logs` | 本次 `sessionId`、最近 10 分钟、类别为 rule / network / parse / image / screen / reader / playback 的本机日志行原样，最多 300 条、128 KB；用户关掉开关时不带 |

- 网址清洗（App 与 PortalCore 同一套规则）：去掉 user:pass@、查询串与片段；路径段命中任一条即换成 :token——JWT 形状
  （eyJ 开头且含两个点）、前一段是 token / auth / session / sign / key 一类的段名、长度不小于 32 且同时含大写、小写与数字的
  base64url 串。只由十六进制组成、长度不超过 40 的段保留（多半是章节或图片 ID）。两边各写一份表驱动测试，用例逐条一致。
- 日志片段不重新脱敏：Release 日志里的路径是哈希、标题只有长度（[Logging-Design.md](Logging-Design.md)），报告里的明文只来自「对象」组。
- 不带截图。

## 七、App 实施清单

分层按 [architecture.md](../architecture.md) 的 `BCA-ARCH-003`、`BCA-ARCH-004` 与 `BCA-OBS-003` 放。

| 位置 | 内容 |
| --- | --- |
| Shared/Diagnostics | 新增失败快照与快照存储，`RuleFailureDiagnostics.report` 在上报之后写入；内存里留最近 20 条，按（失败点，来源 ID）取（`BCA-OBS-020`） |
| 规则错误摘要 | `RuleExecutionError` 实现 `DiagnosticSummaryProviding`：只写 case 名、状态码、阶段、ruleID、operation，不写网址；现有日志与 Crashlytics 的摘要随之变清楚 |
| Shared/Logging | `AppLogging` 加一个取日志片段的方法，复用本机日志文件的读取逻辑；按会话、时间窗、类别、条数与字节上限取，取之前先 `AppLog.flush()` |
| Application | 报告模型、发送端口与发送用例：拼报文、清洗网址、截断补充说明，已登录时带令牌；日志片段经一个端口取，由组合根装配（Shared 不得引用 Application） |
| Application · 规则目录 | `AddCatalogSourceUseCase` 在添加来源与跟随更新时写 `catalogRevision`，「指纹相同、不物化」的分支也写，存量来源刷新一次目录即补齐 |
| Infrastructure | 报告发送的 APIKit 适配器，服务端错误码映射成「太频繁」「发送失败」两类；`sources` 追加 `catalogRevision` 列（只追加迁移），`GRDBSourceRepository` 读写它 |
| BrowseCraftAPIKit | `PortalAPIConfiguration` 加 `/v1/problem-reports`；`PortalAPIClient` 加发送方法，令牌可选、经 `sendData` 发送；目录来源载荷解出明文 `catalogSHA256` |
| Features/Shared | 报告面板、页面上下文（screen + scope + 来源 + 对象 + 可空的失败点）、小字链接与「…」菜单两个小组件；`LibraryStateBanner` 加可选的报告动作 |
| Features 各页 | 第三节的页面各接两个入口，上下文从各自的 ViewModel 拼；详情页的「…」在 `DetailTopButtons` 里加一个，影视详情另加 |
| 日志 | `diagnostics` 类别记 notice `problem-report-submitted` 与 error `problem-report-failed`，字段为 scope、问题码、报告编号的 `.id` 哈希与耗时 |
| 本地化 | 三份 Localizable.strings：问题类型、面板文案、结果与失败文案 |
| 测试 | 快照存储、网址清洗（含带令牌的查询串、片段、user:pass@ 与路径令牌段）、报文拼装、日志片段截取、各 scope 的问题类型表 |
| 隐私 | `PrivacyInfo.xcprivacy` 的其他诊断数据为关联，并声明客户支持、浏览历史、搜索历史三类（用途 App 功能、不追踪）；App Store Connect 隐私标签与 PortalCore 隐私权政策页的「問題回報」一节同口径 |

## 八、书阅读器单章失败（前置项）

站点书单章正文失败时，除「网页上没有正文」之外的失败（网络失败、站点 403 / 5xx、反爬页、选择器取不到、规则配置错）
目前变成 Readium 的访问失败，`BookReaderView` 的 `onError` 为空闭包，不出 App 自己的提示，也不经 `RuleFailureDiagnostics`。
报告要报得准，先接住这一路：

- 新增失败点 `book_reader_chapter`：在 `BookReaderViewModel` 里给章节内容提供方包一层，在 catch 里经
  `RuleFailureDiagnostics.report` 上报，`SourceRuntimeError` 的 emptyContent 不报；Readium 预加载前后若干章，
  同一章在一次阅读里只报一次。上报放在 Features 层，与其余页面一致。
- 其余失败也渲染说明页（与 emptyContent 同一种渲染，另加三语文案），说明页下放「报告问题」；`onError` 至少记一条
  error 日志（`BCA-OBS-015`）。
- 实施前先在模拟器上断网翻到没预加载过的章节，看一眼现在的画面，确认说明页要改什么。

## 九、服务端依赖（PortalCore）

问题报告与服务端的失败生成**分开收集、按规则合着看**：两者是规则在不同阶段的问题，证据与隐私口径不同，表、接口与保留期都不合并，
只在第 4 步的查询里按规则汇合，最后进同一条 fwq 修复队列。两边各守现有纪律：诊断写入失败只记日志，不影响任务结局、coin、
推送与报告的接收。

| 位置 | 内容 |
| --- | --- |
| `POST /v1/problem-reports` | 新模块 problem_reports（router / schemas / repository / contracts 与一版迁移）。请求体为第六节的 JSON，不超过 256 KB，在应用层拒绝。带 Bearer 时归到账号，不带时按诊断码收。同一 `clientReportId` 再次提交返回同一编号。返回 `{"reportId": "R-7KQ2-M9XA", "receivedAt": "…"}`，错误体沿用 `{code, message, requestId}` |
| 限流 | 计数直接查报告表：每个账号或诊断码每小时 10 条、每天 30 条；未登录另按 IP 每小时 20 条（IP 取已由 nginx 覆盖过的客户端地址），全站未登录每天 2000 条总闸。超出回 429 与 `report_rate_limited`。不用进程内存里的限流器：重启清零、多进程不共享 |
| 服务端清洗 | 按第六节的规则再洗一遍网址，截断日志条数与长度、补充说明长度 |
| 报告表 | 报告编号、`clientReportId`（唯一）、账号 ID（可空）、诊断码、`sourceId`、`ruleRevision`、`revisionMatch`、`scope`、`problemType`、`screen`、失败点、站点侧标记、App 版本、整份报文、接收时间、处理状态（new / triaged / fixed / wontfix）。索引：诊断码、（`sourceId`, `ruleRevision`）、接收时间。保留 90 天，每日任务清理；删号流程一并删除 |
| 站点侧标记 | 失败快照为网络失败、HTTP 429 / 5xx 或反爬页时记为站点侧；403 不记（UA 引起的 403 属于规则） |
| 请求日志 | 只记报告编号、scope 与大小，不记报文 |
| 规则版本表 | 只追加的 `catalog_source_revisions`：来源 ID、`catalog_sha256`、整份 `rule_json`、生效时间。写入挂在唯一写 `rule_json` 的仓储方法里，与索引指纹刷新同一事务，指纹变了才追加；迁移把现有来源回填为第一版。每个来源保留最近 20 版，被未过期报告引用的不删 |
| 目录接口 | 每个来源多返回明文 `catalogSHA256`（服务端现成的指纹，不含规则内容） |
| 版本对照 | 先按（`sourceId`, `ruleRevision`）取版本，记 `revisionMatch` 为 exact；为空时取 `ruleAppliedAt` 之前最近的一版，记 by_time；版本表建立之前的记 unknown |

开发者的排查与查询脚本：

1. 按报告编号或诊断码取出报告，看失败快照与日志片段。
2. 按 `sourceId` + `ruleRevision` 从版本表取出那一版规则原文；`revisionMatch` 不是 exact 时先核对版本；与目录当前版不同说明用户还在用旧规则。
3. 拿 `targetURL` 与 scope 对应的阶段，在 fwq 里用同一版规则重放那一页，复现后开 fwq 侧的修复项。
4. 汇总查询：按（`sourceId`, `ruleRevision`, scope）数最近 24 小时的报告，默认不计站点侧，另列一行看站点可用性。
5. 按规则汇总查询：输入 `sourceId`（可选 `ruleRevision`），输出这条规则当初的生成任务与结局（经 `generated_rule_index` 按指纹对到任务，
   有花了 token 的失败归档时一并列出）、该站最近的生成成功与失败数、最近 24 小时的报告数（按问题码与站点侧分开）。

第 4、5 步只做脚本，不做自动告警。

## 十、埋点登记

以下名字在实施时与代码同一提交登记进 [Analytics-Events-Design.md](Analytics-Events-Design.md)（`BCA-OBS-001`；闸门 A13 双向核对，
不能先于代码登记）：

| 登记处 | 内容 |
| --- | --- |
| 第 3 节 A 组 | 事件 `problem_report_submitted`：点「发送」后的结局报一次，参数 `report_scope`、`problem_type`、`entry`（failure_state / page_menu）、`result`（success / failed）、`error_code`（仅失败）。不报：补充说明、报告编号、网址、标题与搜索词 |
| 第 4 节 | 参数 `report_scope`（第三节的 scope）、`problem_type`（第五节的问题码）；GA4 事件级自定义维度由 24 个增至 26 个 |
| 第 5 节 | 页面 `problem_report`：报告问题面板（sheet） |
| 第 6.1 节 | 失败点 `book_reader_chapter`（第八节），阶段 reader；与第 3 节 I 组一一对应的规则执行失败点由十四个增至十五个 |

## 十一、分期

- 前置（与报告入口无关，可先做）：第八节书阅读器单章失败；`RuleExecutionError` 的脱敏摘要。
- 第一期：PortalCore 报告接口与表、规则版本表与目录指纹字段；App 的 `catalogRevision` 迁移与写入、快照存储、报告面板、
  用例与客户端；第三节标「一」的七个页面的两个入口；埋点登记。PortalCore 先上线，App 后发版。
- 第二期：有声书、视频播放器、来源页、规则目录四处；第九节第 4、5 步的查询脚本。
- 看数据再定：截图、处理进度回执、同一规则报告变多时自动告警、fwq 按报告编号重放。
