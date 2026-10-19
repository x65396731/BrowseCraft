# 页内问题报告

设计文档（含两个入口、报告面板与数据流三张图）：[BrowseCraft 页内问题报告入口设计书](https://claude.ai/artifact/R1jd8HR8q6hKoSKh1vTjMB)。
设计与实施状态见 [STATUS.md](../STATUS.md)。面板版式沿用网址输入页的重新生成面板，颜色只取规则目录的色板
（[网址输入页](Generation-Input-Page-Redesign-Design.md)、[规则目录](Catalog-Page-Redesign-Design.md)），App 内不新增色值。

## 一、范围

库页与三种详情页（漫画、影视、站点书）有一个同一形态的「报告问题」入口。详情页的报告既可以针对详情与目录，也可以针对
某一集（话、章）的内容：阅读器与播放器里遇到的问题，退回详情页、在面板里选是哪一集来报。用户点「发送」后，App 把
「哪条规则、哪一版、在哪个阶段、对哪一页、出了什么错」打包发给 PortalCore，换回一个报告编号；开发者按编号、诊断码或
来源与规则版本查询。

不在本文范围：来源内搜索、阅读器、有声书、视频播放器、来源页与规则目录上的入口；客服对话与处理进度回执（只回编号）、
截图、自动上报、给报告发 coin、规则执行本身与现有埋点和 Crashlytics 的采集范围。邮件方案（面板把报告与日志打成文件、
走系统分享面板）只作服务端不可用时的兜底。

## 二、条款

- `BCA-OBS-018` 问题报告只在用户点面板上的「发送」时离开设备。App 不得自动、定时或在后台发送报告，发送失败也不得
  自动重试，只给「再试一次」。「发送使用统计」与「发送崩溃诊断」两个开关不管报告，与导出诊断日志同一原则（`BCA-OBS-016`）；
  面板自身的埋点仍受使用统计开关管（`BCA-OBS-005`）。
- `BCA-OBS-019` 报告只发第六节登记的字段。任何情况下不得发送：Cookie、站点登录凭据、授权头、令牌、网址查询串与片段、
  网页源码片段、规则错误的 `errorDescription` 原文（它内嵌完整网址）、搜索词、设备标识与 Apple 账号标识。对象网址只留 scheme、
  主机与路径，路径按第六节的规则遮蔽令牌段；App 与 PortalCore 用同一套规则各清洗一遍。作品与章节标题、网址路径只出现在
  报告里，不得因此写进日志、埋点或 Crashlytics（`BCA-OBS-002`、`BCA-OBS-008` 不变）。
- `BCA-OBS-020` 失败快照只由 `RuleFailureDiagnostics.report` 在上报之后写入，只在内存里、不落盘，被挡掉的取消不进快照。
  各页不得自行收集或保存失败快照，面板按（失败点，来源 ID）向快照存储取（`BCA-OBS-007` 的单一入口不变）。
- `BCA-OBS-021` 问题类型是第五节的封闭枚举：面板只显示当前页面与「问题出在哪」对应那一组的选项，「其他」总在最后，
  每组不超过 9 个。新增、改名或改归属先改本文再改代码；服务端按问题码统计，显示文字按内容类型换词、问题码不变。
- `BCA-OBS-022` 报告里的规则版本取 `sources` 表的 `catalogRevision`，即规则目录下发的服务端指纹 `catalogSHA256`。
  本机的 `catalogRuleFingerprint` 只用于判断目录规则是否变化、决定是否跟随更新，不得作为对外的规则版本标识上报：
  它是 App 对重新编码的规则原文算的值，与服务端指纹不同。
- `BCA-UI-006` 只有第三节表中的四个页面有报告入口，每页两个，打开同一个报告面板：失败态上的「报告问题」小字链接，
  以及页面「…」菜单里的「报告这一页的问题」。失败态入口不得做成与「重试」「登录」同级的按钮；受限态（要登录）是预期状态，
  不加入口。阅读器、播放器与其他页面不放入口，也不改它们的界面；阅读与播放的问题从详情页报。

## 三、覆盖页面与入口

入口跟着「这一页显示的是哪一步规则的结果」走。`scope` 是报告对象的枚举，只有三个值：list（库页的列表、当前分类、翻页）、
detail（详情与目录）、content（某一集、话、章的内容，只从详情页报）。

| 页面（`DiagnosticScreen`） | scope | 快照取哪些失败点 | 失败态入口加在哪 | 「…」放在哪 |
| --- | --- | --- | --- | --- |
| `library` 库页 | list | `library_refresh`、`library_pagination` | `LibraryStateBanner` 的失败态、`LibraryPlaceholderView`、`LibraryPaginationFooterView` 的失败文案后 | 页头圆按钮行，搜索与账号圆按钮旁 |
| `comic_detail` 漫画详情 | detail、content | detail 取 `comic_detail`；content 取 `comic_reader` | 横幅失败态、空目录占位 | `DetailTopButtons` 第三个圆按钮 |
| `video_detail` 影视详情 | detail、content | detail 取 `video_detail`；content 取 `video_episode_resolve`、`video_playback` | 横幅失败态、空目录占位 | 页头圆按钮行 |
| `book_detail` 站点书详情（含有声书） | detail、content | detail 取 `book_detail`；content 取 `book_reader_open` | `LibraryStateBanner` 的失败态 | `DetailTopButtons` |

- 失败态入口：`LibraryStateBanner` 加可选的报告动作，在说明句下多一行动作蓝小字「报告问题」，右侧「登录」「重试」不动；
  空列表占位放在重试按钮下；翻页脚放在失败文案后。
- 常驻入口：一个与旁边收藏、搜索、账号同样式的「…」圆按钮，点开是系统菜单，其中一项「报告这一页的问题」
  （图标 exclamationmark.bubble）。以后的「分享」「用浏览器打开」也放这个菜单。
- 阅读器与播放器出错时照旧经 `RuleFailureDiagnostics.report` 上报，不加任何入口；用户退回详情页报 content 时，面板取得到那条快照。

## 四、报告面板

底部面板，中号高度、可拉到大号，版式同 `RegenerateRuleSheet`，颜色只取 `CatalogPalette`。从失败态进来时预选「加载失败」、
对象卡下写出当时的失败文案；从「…」进来不预选、没有警示行。

| 块 | 内容 |
| --- | --- |
| 顶部 | 抓手；28pt 动作蓝图标圆 + 标题「报告问题」；一句「会把下面的信息发给开发者，用来查这条规则。」 |
| 对象行 | 小卡：类型色图标 + 来源名 · 页面名（如「笔趣阁 · 详情」）；从失败态进来时卡下一行警示色小字写当时的失败文案 |
| 问题出在哪（只在详情页） | 两段选择「详情与目录」｜「某一集的内容」（漫画写「某一话」，书写「某一章」）。从失败态进来固定为「详情与目录」；从「…」进来默认「详情与目录」，本次启动里这个来源刚有过阅读或播放失败时默认「某一集的内容」。切换时问题类型换成对应的一组 |
| 哪一集（选了内容才有） | 一行「哪一集：上次看到 第 12 集 ›」。默认取历史里的上次看到 / 读到，没有历史时取第一集；点开是详情页已加载的目录，影视先选线路再选集，选中即回到面板。目录为空时「某一集的内容」不可选 |
| 站点侧提示 | 失败快照属于网络失败、反爬页、HTTP 429 / 5xx 或需要账号时，问题类型上方一行灰字「看起来是网站暂时打不开或要登录，不一定是规则的问题；仍然可以报告。」不拦发送 |
| 问题类型 | 单选芯片，按第五节给当前那一组的选项 |
| 补充说明 | 可选文本框，占位「例如：第 3 页之后都是同一张图」，最多 500 字 |
| 将发送的信息 | 默认收起的一行「将一并发送：页面、规则版本、失败信息、最近 10 分钟的诊断日志」，展开逐项列出第六节的字段与取值（网址为清洗后的值）；日志一项带开关，默认开 |
| 主按钮 | 蓝色胶囊「发送」，发送中转圈；不扣 coin，不用滑动确认 |
| 结果 | 成功：面板换成 `StatusCardView`（蓝 ✓）「已发送」+ 报告编号（形如 R-7KQ2-M9XA，点一下复制）+「联系我们时报这个编号」，下方「完成」。失败：警示色小字 +「再试一次」，已填内容不丢；服务端回限流时写「发得太频繁了，稍后再试」 |

## 五、问题类型

每组的选项（显示文字按类型换词：集 / 话 / 章；库页的「最新」指封面下的最新一集 / 话 / 章；书详情的内容组按来源是文字书
还是有声书给对应的一组）：

| 位置 | 影视 | 漫画 | 书（含有声书） |
| --- | --- | --- | --- |
| 库页 | 加载失败 · 列表是空的 · 封面不显示 · 标题不对 · 「最新」不对 · 分类不对 · 翻页出错 · 乱码 · 其他 | 同左 | 同左 |
| 详情页 · 详情与目录 | 加载失败 · 没有剧集 · 集数不全 · 线路混在一起 · 顺序不对 · 简介或信息不对 · 封面不显示 · 其他 | 加载失败 · 没有章节 · 章节不全 · 顺序乱或重复 · 付费章节没标出 · 简介或信息不对 · 封面不显示 · 其他 | 加载失败 · 目录是空的 · 目录不全 · 顺序乱或重复 · 章节名乱码 · 简介或信息不对 · 封面不显示 · 其他 |
| 详情页 · 某一集的内容 | 播不出来 · 不是这一集 · 广告或跳转 · 打开的是网页 · 一直在加载 · 换线路也不行 · 登录后仍看不了 · 其他 | 打不开 · 一页都没有 · 图片加载不出 · 少页 · 顺序乱或重复 · 混进别的图 · 登录后仍看不了 · 加载很慢 · 其他 | 文字书：打不开 · 空白或只有标题 · 少了段落 · 只有一部分 · 夹着广告或杂字 · 乱码 · 不是这一章 · 其他。有声书：播不出来 · 不是这一章 · 时长或进度不对 · 登录后仍听不了 · 其他 |

问题码（`problem_type` 的取值，共 30 个）：

| 问题码 | 显示文字 | 用在 |
| --- | --- | --- |
| `load_failed` | 加载失败 / 打不开 | 库页、详情、漫画与文字书的内容 |
| `playback_failed` | 播不出来 | 影视与有声书的内容 |
| `list_empty` | 列表是空的 | 库页 |
| `cover_missing` | 封面不显示 | 库页、详情 |
| `title_wrong` | 标题不对 | 库页 |
| `latest_wrong` | 「最新」不对 | 库页 |
| `category_wrong` | 分类不对 | 库页 |
| `pagination_wrong` | 翻页出错 | 库页 |
| `garbled_text` | 乱码 / 章节名乱码 | 库页、书详情、文字书的内容 |
| `toc_empty` | 没有剧集 / 没有章节 / 目录是空的 | 三种详情 |
| `toc_incomplete` | 集数不全 / 章节不全 / 目录不全 | 三种详情 |
| `lines_mixed` | 线路混在一起 | 影视详情 |
| `order_wrong` | 顺序不对 / 顺序乱或重复 | 三种详情、漫画的内容 |
| `lock_unmarked` | 付费章节没标出 | 漫画详情 |
| `info_wrong` | 简介或信息不对 | 三种详情 |
| `wrong_item` | 不是这一集 / 不是这一章 | 影视、文字书与有声书的内容 |
| `ads_or_redirect` | 广告或跳转 | 影视的内容 |
| `web_fallback` | 打开的是网页 | 影视的内容 |
| `stuck_loading` | 一直在加载 | 影视的内容 |
| `all_lines_failed` | 换线路也不行 | 影视的内容 |
| `paywall_after_login` | 登录后仍看不了 / 仍听不了 | 影视、漫画与有声书的内容 |
| `content_empty` | 一页都没有 / 空白或只有标题 | 漫画与文字书的内容 |
| `images_not_loading` | 图片加载不出 | 漫画的内容 |
| `content_missing` | 少页 / 少了段落 | 漫画与文字书的内容 |
| `non_content_images` | 混进别的图 | 漫画的内容 |
| `slow` | 加载很慢 | 漫画的内容 |
| `chapter_partial` | 只有一部分 | 文字书的内容 |
| `junk_text` | 夹着广告或杂字 | 文字书的内容 |
| `progress_wrong` | 时长或进度不对 | 有声书的内容 |
| `other` | 其他 | 各组 |

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
| 对象 | `targetURL` | 当前列表页或详情页的网址；scope 为 content 时取目录里那一集（话、章）的网址。按下文清洗 |
| 对象 | `targetTitle`、`chapterTitle`、`chapterIndex` | 作品名；scope 为 content 时的集（话、章）名与序号，影视的集名带线路名 |
| 对象 | `categoryKey` | 库页分类键 |
| 失败快照 | `failure` | 失败点、阶段、类别、错误 case 名、状态码、ruleID、operation、选择器、脱敏摘要、发生时间，取自 `RuleExecutionError` 的 case 与关联值。scope 为 content 时取本次启动里同一来源最近一次第三节所列内容失败点的快照；没有对应失败时为空 |
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
| Features/Shared | 报告面板（含「问题出在哪」两段选择与选集行）、页面上下文（screen + scope + 来源 + 对象 + 可空的失败点）、小字链接与「…」菜单两个小组件；`LibraryStateBanner` 加可选的报告动作 |
| Features 各页 | 库页与三种详情页各接两个入口，上下文从各自的 ViewModel 拼；详情页另提供目录（已加载的数据）与上次看到 / 读到（取自历史）给选集行；详情页的「…」在 `DetailTopButtons` 里加一个，影视详情另加 |
| 日志 | `diagnostics` 类别记 notice `problem-report-submitted` 与 error `problem-report-failed`，字段为 scope、问题码、报告编号的 `.id` 哈希与耗时 |
| 本地化 | 三份 Localizable.strings：问题类型、面板文案、结果与失败文案 |
| 测试 | 快照存储、网址清洗（含带令牌的查询串、片段、user:pass@ 与路径令牌段）、报文拼装、日志片段截取、各组的问题类型表、选集默认值 |
| 隐私 | `PrivacyInfo.xcprivacy` 的其他诊断数据为关联，并声明客户支持与浏览历史两类（用途 App 功能、不追踪），不声明搜索历史；App Store Connect 隐私标签与 PortalCore 隐私权政策页的「問題回報」一节同口径 |

## 八、书阅读器单章失败（可选）

站点书单章正文失败时，除「网页上没有正文」之外的失败（网络失败、站点 403 / 5xx、反爬页、选择器取不到、规则配置错）
变成 Readium 的访问失败，`BookReaderView` 的 `onError` 为空闭包，不出 App 自己的提示，也不经 `RuleFailureDiagnostics`。
这一路不挡报告入口：从书详情报某一章时报告里没有快照，但日志片段有阶段失败记录。要单独改进时：

- 新增失败点 `book_reader_chapter`：在 `BookReaderViewModel` 里给章节内容提供方包一层，在 catch 里经
  `RuleFailureDiagnostics.report` 上报，`SourceRuntimeError` 的 emptyContent 不报；同一章在一次阅读里只报一次。
  新失败点先登记进埋点合同第 6.1 节，书详情的内容组随之也取它的快照。
- 其余失败也渲染说明页（与 emptyContent 同一种渲染，另加三语文案）。说明页渲染在 Readium 正文里，只写文字、不放链接；
  `onError` 至少记一条 error 日志（`BCA-OBS-015`）。

## 九、服务端依赖（PortalCore）

问题报告与服务端的失败生成**分开收集、按规则合着看**：两者是规则在不同阶段的问题，证据与隐私口径不同，表、接口与保留期都不合并，
只在第 5 步的查询里按规则汇合，最后进同一条 fwq 修复队列。两边各守现有纪律：诊断写入失败只记日志，不影响任务结局、coin、
推送与报告的接收。

| 位置 | 内容 |
| --- | --- |
| `POST /v1/problem-reports` | 新模块 problem_reports（router / schemas / repository / contracts 与一版迁移）。请求体为第六节的 JSON，不超过 256 KB，在应用层拒绝。带 Bearer 时归到账号，不带时按诊断码收。同一 `clientReportId` 再次提交返回同一编号。返回 `{"reportId": "R-7KQ2-M9XA", "receivedAt": "…"}`，错误体沿用 `{code, message, requestId}` |
| 限流 | 次数上限直接查报告表计数：每个账号或诊断码每小时 10 条、每天 30 条，全站未登录每天 2000 条总闸；不用进程内存里的限流器（重启清零、多进程不共享）。未登录另按 IP 每小时 20 条，IP 取已由 nginx 覆盖过的客户端地址，用进程内滑动窗口，只作粗粒度防刷。超出回 429 与 `PROBLEM_REPORT_RATE_LIMITED` |
| 服务端清洗 | 按第六节的规则再洗一遍网址，截断日志条数与长度、补充说明长度 |
| 报告表 | 报告编号、`clientReportId`（唯一）、账号 ID（可空）、诊断码、`sourceId`、`ruleRevision`、服务端对到的那一版指纹（`matched_revision`，按指纹或按时间）、`revisionMatch`、`scope`、`problemType`、`screen`、失败点、站点侧标记、App 版本、整份报文、接收时间、处理状态（new / triaged / fixed / wontfix）。索引：诊断码、（`sourceId`, `ruleRevision`）、接收时间。保留 90 天，收报告时顺带清理（一个进程里最多每 6 小时一次）；已登录的报告随账号外键级联删除 |
| 站点侧标记 | 失败快照为网络失败、HTTP 429 / 5xx 或反爬页时记为站点侧；403 不记（UA 引起的 403 属于规则） |
| 请求日志 | 只记报告编号、scope 与大小，不记报文 |
| 规则版本表 | 只追加的 `catalog_source_revisions`：来源 ID、`catalog_sha256`、整份 `rule_json`、生效时间。写入挂在唯一写 `rule_json` 的仓储方法里，与索引指纹刷新同一事务，指纹变了才追加；迁移把现有来源回填为第一版。每个来源保留最近 20 版，被未过期报告引用（`matched_revision`）的不删，与过期报告同一次清理 |
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

以下名字登记在 [Analytics-Events-Design.md](Analytics-Events-Design.md)（`BCA-OBS-001`；闸门 A13 双向核对字典与代码）：

| 登记处 | 内容 |
| --- | --- |
| 第 3 节 A 组 | 事件 `problem_report_submitted`：点「发送」后的结局报一次，参数 `report_scope`、`problem_type`、`entry`（failure_state / page_menu）、`result`（success / failed）、`error_code`（仅失败）。不报：补充说明、报告编号、网址与标题 |
| 第 4 节 | 参数 `report_scope`（第三节的 scope）、`problem_type`（第五节的问题码）；GA4 事件级自定义维度由 24 个增至 26 个 |
| 第 5 节 | 页面 `problem_report`：报告问题面板（sheet） |

## 十一、分期

- 第一期（唯一一期）：PortalCore 报告接口与表、规则版本表与目录指纹字段；App 的 `catalogRevision` 迁移与写入、
  `RuleExecutionError` 的脱敏摘要、快照存储、报告面板（含「问题出在哪」与选集）、用例与客户端；库页与三种详情页的两个入口；
  埋点登记。PortalCore 先上线，App 后发版。
- 第一期之后：第九节第 4、5 步的查询脚本。
- 可选：第八节书阅读器单章失败。
- 看数据再定：截图、处理进度回执、同一规则报告变多时自动告警、fwq 按报告编号重放。
