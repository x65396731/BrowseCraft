# 实施状态

本文是瞬时状态的唯一承载，形态与取值由 [文档索引](README.md) 第 5 节定义。
C 类设计文档不再承载 `implemented` / `pending` / `passed` 这类状态。

每格恰好一个值（`BCA-DOC-004`）。一个工作项同时存在多种验证事实时拆成多行（`BCA-DOC-005`）。
被覆盖的旧值追加到 [history/status-log.md](history/status-log.md)（`BCA-DOC-006`）。

条款列写 `未编号` 的行，是条款编号（D3）尚未执行的结果，不是「没有约束」。

## 0. 读这张表的纪律

**本表的行不会随条款落地自动退休。** 开工前的三步核对（都是零成本）：在 `BrowseCraft/` 与五个包里
grep 该行点名的类型或文件，看有没有实现；在本表里交叉查同一工作项有没有别的行标了 `implemented`；
该项若有产物可查（真机日志、模拟器截图、测试产物），按产物时间线看症状还在不在。

并且要看全五个状态列——`设计` 列为 `superseded` 就说明该设计已被取代，此时 `实施=not-started`
是正确的记法而不是过期。

`验证` 列的三级不可互相推断：`full-suite-passed` 是离线测试全过，`simulator-passed` 是模拟器上
人工走通了流程，`device-passed` 是用户在真机上确认。模拟器通过**不等于**真机通过。

## 1. 读书 kind（book）

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 读书 kind App 侧接线立项（三批范围、五仓改动清单、目录接口封闭枚举的兼容硬约束与发布策略） | `BC-BOOK-001` `BC-BOOK-012` | required | approved | implemented | full-suite-passed | 7ae4270 | 2026-09-13 |
| 批次 A：APIKit / Core / Domain 的 book 枚举与 `BookSiteRuleValidator`、各分流点补 book | `BC-BOOK-001` | required | approved | implemented | full-suite-passed | 43dfef2 | 2026-09-14 |
| 批次 B：Runtime 按规则取正文与音频、RWPM 装配、Readium 出版物构建 | `BC-BOOK-012` | required | approved | implemented | full-suite-passed | ac37e7f | 2026-09-14 |
| 批次 C：添加来源入口、站点书详情、共用 EPUB 阅读器、`SiteBookIdentity` 与迁移 v4 | `BC-BOOK-012` | required | approved | implemented | full-suite-passed | 8b280ff | 2026-09-14 |
| 站点书整链（sfacg 添加 → 列表 → 作品 → 章节 → 正文 → 续读） | `BC-BOOK-012` | required | approved | implemented | device-passed | 9b3a7d8 | 2026-09-15 |
| 站点有声作品的播放器（AudioNavigator 内核、远程 mp3 经 HTTPContainer、锁屏控制） | `BC-BOOK-012` | required | approved | implemented | simulator-passed | 11821b6 | 2026-09-14 |
| 站点书搜索：由规则声明，与漫画 / 影视同一条合同 | `BC-SEARCH-004` | required | approved | implemented | full-suite-passed | 84af71b | 2026-09-15 |
| 站点书进 History 页：与漫画、视频同列 | 未编号 | required | approved | implemented | full-suite-passed | 79512a9 | 2026-09-16 |
| book catalog 不发布进公共目录——2026-09-14 用户裁决发布 biquhua 后被取代，当前靠服务器 `kinds` 缺省不回 book | `BC-BOOK-001` | rejected | superseded | reverted | not-run | 43dfef2 | 2026-09-14 |
| 四个接口变体（list / detail / reader 的 API 形态）——无语料，另立项 | `BC-BOOK-012` | optional | draft | not-started | not-run | 8b280ff | 2026-09-14 |
| 本地书籍导入 B0：Domain 模型、三个仓储协议、六用例、迁移 v3 与边界脚本禁 Readium | 未编号 | required | approved | implemented | full-suite-passed | 4811cb1 | 2026-09-13 |
| 本地书籍导入 B1：Readium 环境 / 嗅探器 / 打开器、容器内文件存储、三个 GRDB Record 与仓储 | 未编号 | required | approved | implemented | full-suite-passed | 8a5b8a9 | 2026-09-13 |
| 本地书籍导入 B2：书架与 EPUB 阅读器、目录跳转、书签、退出重开续读 | 未编号 | required | approved | implemented | simulator-passed | 1c78bb2 | 2026-09-14 |
| 本地书籍导入 B3：有声书播放器——按「入口不对用户暴露」的裁决不做 | 未编号 | rejected | superseded | not-started | not-run | 1c78bb2 | 2026-09-14 |
| 本地导入入口已藏：去掉 Library 工具栏「书籍」与 RootView 书架装配，代码留给站点抓取路复用 | 未编号 | required | approved | implemented | full-suite-passed | 1c78bb2 | 2026-09-14 |
| Readium Swift Toolkit 3.11.0 选型与 SwiftSoup fork 覆盖 | 未编号 | required | approved | implemented | full-suite-passed | 7ad2704 | 2026-09-13 |
| SwiftSoup 切回官方 2.14.3（上游 #461 修了 inline 空白、我方 PR #462 经 #467 合入，两者都在 2.14.3）：Core 改精确锁定官方 tag，删 `../SwiftSoup` 本地覆盖包、`check-swiftsoup-override.sh` 与预构建阶段，`BCA-BUILD-002` 改口；同批小版本：Alamofire 5.11.2 → 5.12.2、Readium 3.11.0 → 3.11.1、WebUI 4.4.0 → 4.5.0。Core 305 个测试对官方 2.14.3 全过，Runtime 46 个全过，App 目标 XCTest 86 + Swift Testing 670 全过（`ReadinessSelectorContentSemanticsTests` 的计时用例整套跑时因并行编译偶红、单独重跑 1198 ms 通过，与 HANDOFF 所记一致）。Xcode 27.0 在工程文件与包图被替换时崩过一次（SwiftPM `SPMPIFBuilder.build()`），重开即可，与 App 无关 | `BCA-BUILD-002` | required | approved | implemented | full-suite-passed | 3fd3ebde | 2026-10-20 |
| PDF 与 CBZ 不接（PDF 见 `BC-BOOK-012`，CBZ 漫画线保持自研阅读器） | `BC-BOOK-012` | rejected | approved | not-started | not-run | f443602 | 2026-09-13 |
| 站点有声播放器后续项：界面样式、倍速与偏好入口（SDK 有 `AudioPreferences`，界面没露）、`mediaAPI` 与带签名音频（无语料）——从读书接线合同第十六节搬出立行 | `BC-BOOK-012` | optional | draft | not-started | not-run | 1c7bc61 | 2026-10-10 |
| 有声书后台续播与迷你播放条（播放页裁定 10：离开本页即停播，不做；另立项后再排期） | 未编号 | optional | draft | not-started | not-run | 4a83331 | 2026-10-20 |

## 2. 规则目录

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 已添加来源的「更新规则」入口——被「已添加来源跟随目录自动更新」取代 | 未编号 | rejected | superseded | reverted | not-run | 175847d | 2026-09-30 |
| 已添加来源跟随目录自动更新（目录页读取、启动与回到前台时静默覆盖本地副本） | 未编号 | required | approved | implemented | targeted-passed | 3646c2e | 2026-09-30 |
| 同站多条来源的副标题显示各自入口地址 | 未编号 | required | approved | implemented | device-passed | 1513a0f | 2026-09-15 |
| 规则目录页重设计：推荐 / 我的生成分栏，推荐按类型分区，我的生成按时间线（方案 A） | 未编号 | required | approved | implemented | full-suite-passed | 9c03d27 | 2026-09-30 |
| 来源页重设计：正在使用置顶、点来源即打开库、已暂停区与启用窗口、长按菜单（方案 A） | 未编号 | required | approved | implemented | full-suite-passed | 2c0908a | 2026-10-01 |
| 来源页重设计的模拟器走查：切换成功跳库 / 失败留在原页、「更多位置」打开购买页、iCloud 恢复失败下拉重试（来源页与收藏页） | 未编号 | required | approved | implemented | simulator-passed | 448615c | 2026-10-01 |
| 收藏页重设计：封面卡片行、类型筛选（全部与三类一直显示）、按天分组、左滑取消收藏与撤销、来源状态 | 未编号 | required | approved | implemented | full-suite-passed | a5dc313 | 2026-10-03 |
| 收藏页重设计的模拟器走查：筛选与某类为 0、按天分组、左滑与长按取消收藏及撤销、在库中查看来源、三种来源状态、空状态与恢复失败下拉重试、深色、库页爱心同步 | 未编号 | required | approved | implemented | simulator-passed | a5dc313 | 2026-10-03 |
| 历史页重设计：继续卡片、看到哪里与视频进度、类型筛选、按天分组、按作品删除与撤销、来源状态；封面与撤销提示条与收藏页共用 | 未编号 | required | approved | implemented | full-suite-passed | 9ebb107 | 2026-10-03 |
| 设置页重设计：自绘大标题、账号卡（余额与看广告 +N、未登录系统登录按钮与不计奖励的看广告）、高级版入口卡、同步与存储 / 隐私与诊断 / 关于三组卡片行、退出登录确认框；下线书签页、复制诊断码行与两张图标 | 未编号 | required | approved | implemented | full-suite-passed | 3129a73 | 2026-10-03 |
| 设置页重设计的模拟器走查：未登录浅色与深色、系统登录按钮、未登录看广告（加载中、播完提示不计 coin）、已登录浅色与深色（临时注入）、诊断码与账号 ID 复制、退出确认框、进入 coin 记录子页 | 未编号 | required | approved | implemented | simulator-passed | 3129a73 | 2026-10-03 |
| coin 记录页重设计：隐藏底栏只留返回、余额卡与服务端价格说明、按天分组的卡片行、获得蓝底与消耗灰底图标、获得色 `gain`、骨架、失败与空状态可下拉、翻页与到底提示 | 未编号 | required | approved | implemented | full-suite-passed | ea2fefc | 2026-10-03 |
| coin 记录页重设计的模拟器走查（真实登录账号）：底栏隐藏只留返回、返回后底栏恢复、余额卡与价格说明、按天分组与跨天翻页到底、六种原因图标与获得色、深色、内购页仍隐藏底栏 | 未编号 | required | approved | implemented | simulator-passed | ea2fefc | 2026-10-03 |
| 缓存页重设计：隐藏底栏、用量卡（两块图片缓存分开计、写合计最多）、封面与漫画页上限、清除不弹确认并补清列表缩略图与网页 / 系统网络缓存（不碰 Cookie 与本地存储）、清除结果 | 未编号 | required | approved | implemented | full-suite-passed | e879196 | 2026-10-03 |
| 缓存页重设计的模拟器走查（真实登录账号）：底栏隐藏只留返回、用量与磁盘实测一致、清除后两块图片缓存归零并显示释放结果、Cookie / 网页本地存储 / 数据库未动而网络缓存已清、改上限后合计最多随之变化、深色、返回后底栏恢复 | 未编号 | required | approved | implemented | simulator-passed | e879196 | 2026-10-03 |
| 云同步页重设计：隐藏底栏只留返回、状态卡（按优先级只取一种状态）、开关、同步的内容（来源与收藏带条数、历史与阅读进度按作品计数——续看位置同步落地后改口）、上次同步一行、下拉代替刷新 / 关联 / 同步 / 重试四个按钮、首次开启窗口改卡片样式；删去不再使用的词条 | 未编号 | required | approved | implemented | full-suite-passed | 7f42ed9 | 2026-10-04 |
| 云同步页重设计的模拟器走查（真实登录账号）：底栏隐藏只留返回、返回后底栏恢复、未开启、条数与数据库一致、正在检查 iCloud、首次开启窗口并选「合并本机数据」、正在同步、已同步与上次同步一行、下拉同步、同步出错卡、关闭再打开开关、深色；未登录 iCloud 与提交中状态未走到 | 未编号 | required | approved | implemented | simulator-passed | 7f42ed9 | 2026-10-04 |
| 添加来源页重设计：三张类型横幅（沿用目录页插画）、「接下来」三行、coin 与登录提示、目录入口卡、选类型 / 引导屏 / 输入页同一层 sheet、删 scriptSource 分支与三枚徽章图（七项裁定全取 A） | `BCA-UI-003` | required | approved | implemented | full-suite-passed | c856a0c | 2026-10-06 |
| 添加来源页重设计的模拟器走查（真实登录账号）：已登录浅色与深色、点目录入口卡先收起本页再弹目录、点类型卡在同一层进输入页、输入页关闭回来源页；未登录、余额未同步、从目录空状态进入三种未走到 | `BCA-UI-003` | required | approved | implemented | simulator-passed | c856a0c | 2026-10-06 |
| 网址输入页与引导屏重设计：网址卡带系统粘贴按钮、四步进度卡、结论卡与结果卡共用状态卡、取页方式两个按钮（困难按钮渐变发光描边）、滑动确认代替生成按钮（困难档粉彩流光点阵 + 渐变字与滑块）、网址错误不出卡、引导屏卡片化（六项裁定全取 A，动画与颜色经多轮裁定） | `BC-PAGE-060` | required | approved | implemented | not-run | 7b05a0e | 2026-10-07 |
| 网址输入页与引导屏重设计的模拟器走查（真实登录账号）：空输入、已输入与清除、网址错误（5xx 与 scheme）不出卡、首页检查得「这一页不能用」卡、分类页检查得「可以生成」+ 取页方式按钮 + 余额 + 滑动确认、点困难换成渐变描边与多彩流光一套、滑动确认拖一半弹回、引导屏回看形态、深色、云同步页状态卡复用后不变；检查中的四步进度卡（检查太快没抓到）、真实提交的各结果态（要扣 coin）、粘贴按钮（模拟器剪贴板没同步）未走到 | `BC-PAGE-060` | required | approved | implemented | simulator-passed | 7b05a0e | 2026-10-07 |
| 网址输入页现成规则与取用后（用户 2026-10-19 定，合同第三、六节）：检查可提交时经 `GenerationReusePreviewing` 问 PortalCore `reuse-preview`（PortalCore `21d4e89` 已部署；APIKit 本地未推送），有现成规则时出信息卡、不出取页方式卡、主控件「滑动取用现成规则 · N coin」（本人 7 天内免费取回）；取用后主控件「添加为来源」（`source_added` entry `generation_reuse`），两处重新生成链接拉起 `RegenerateRuleSheet`（取页方式卡 + 滑动重新生成），删去「滑动重新生成」主控件与 `generation_input_reused_hint`；画布第 15 版。模拟器走过：信息卡与取用滑杆、重新生成面板打开与取消不扣费、滑动取用后「添加为来源」加好并收起到库页；未跑单元测试 | 未编号 | required | approved | implemented | simulator-passed | 440ae70 | 2026-10-19 |
| 预检单页超时与引擎对齐（fwq `APP-MEMO-044`；2026-10-19 模拟器验预检放行，tks.tw、bqge.tw 要 16～26 秒才响应，三次 `PreflightPageAcquisitionError` 超时、一次 502，界面「页面暂时无法检查」连提交按钮都出不来）：`VideoGenerationInputSamplingPolicy.requestTimeoutSeconds` 与 `PreflightPageRequest` 默认超时 12 → 25 秒，与引擎直接请求取页一致；全局 deadline 30 秒不动；未 build、未跑测试，待模拟器重交 tks / bqge | `APP-MEMO-044` | required | approved | implemented | not-run | 014b697 | 2026-10-19 |
| 库页视频库重设计：自绘眉行与大标题、搜索与账号两个圆形按钮、视频类型色胶囊分类芯片贴顶、「上次看到」瓷砖（新增按来源取最近视频历史的只读查询）、两列海报墙（集数徽章压封面、爱心用视频强调色）、分页脚代替悬浮胶囊、骨架改两列、横幅与切换来源遮罩换统一取值、空状态新插画 `EmptyStateLibraryVideo`（七项裁定全取 A） | 未编号 | required | approved | implemented | not-run | a5209bf | 2026-10-08 |
| 库页视频库重设计的模拟器走查（真实登录账号，樱花动漫）：眉行与大标题、只有搜索一个圆按钮、芯片选中琥珀、两列海报与爱心、无 `latestText` 故无徽章、滚动后芯片贴顶（状态栏与芯片之间露海报已修）、切分类、进详情与返回、开一集后回库页出现「上次看到」瓷砖（无时长故无进度条）、深色、长按菜单；分页脚、分类出错横幅、切换来源遮罩、账号按钮、点瓷砖进播放器（片源不可用）、搜索结果页、空状态插画实际显示未走到 | 未编号 | required | approved | implemented | simulator-passed | a5209bf | 2026-10-08 |
| 影视详情与选集页重设计：固定深色头图区（海报模糊压暗 + 小海报 + 标题 / 元数据行 / 状态徽章）、右上收藏、通栏「继续看」（按本作品历史写继续 / 下一集 / 再看一遍 / 从第 1 集开始 / 播放）、简介折叠与署名行、线路芯片（与库页分类芯片共用 `LibraryChipBar`）、集号网格（数字集名紧凑、非数字按内容宽、上次看的集描边）、解析时格内转圈不盖遮罩、解析失败横幅；Core `SourceDetailAttribute.key` 透传规则 `metadata[].id`，App 按 key 摆位（八项裁定全取 A） | 未编号 | required | approved | implemented | not-run | 5545183 | 2026-10-08 |
| 影视详情与选集页重设计的模拟器走查（真实登录账号，低端影视）：电影页有历史——深色头图区、小海报、列表标题、元数据行（规则只给 `html[lang]` 的 zh-CN）、「新片」徽章、来源行、继续看按钮、简介展开 / 收起、单集格子描边与小三角；剧集页无历史——「播放」、右上收藏点了变实心且库页爱心同步；深色模式按钮与芯片换浅琥珀底墨字；数字集号网格、线路芯片、正序 / 倒序、下一集 / 再看一遍、受限 / 付费角标、解析失败横幅、没有选集 / 取失败态未走到（模拟器只有一个每部作品一条播放页的来源） | 未编号 | required | approved | implemented | simulator-passed | 5545183 | 2026-10-08 |
| 历史页重设计的模拟器走查：继续卡片三种类型色、看到哪里与进度条、筛选与某类为 0、只有一条、按天分组、左滑与长按删除及撤销（漫画整部删除与整部写回）、在库中查看来源、已暂停 / 已删除 / 未知 / 临时资源、空状态与去库里逛逛、深色、收藏页回归 | 未编号 | required | approved | implemented | simulator-passed | 9ebb107 | 2026-10-03 |
| 收藏页与历史页的选择模式与批量删除（设计稿 2026-10-17 用户确认）：标题行「N 个收藏 / N 条」换成「选择」按钮（当前筛选为空时变灰）；选择模式下标题「已选择 N 部 / 条」+「完成」，筛选变淡不可切，行首勾选框、选中行浅蓝底，历史页继续卡片收回列表，底栏换成操作栏（全选 / 全不选、已选数量、红色取消收藏 / 删除记录），批量前居中确认框；长按菜单加「选择多项」；去掉两页的撤销提示，左滑不再一滑到底；共用零件 ContentSelectionComponents；三语文案 | 未编号 | required | approved | implemented | targeted-passed | 6a702af | 2026-10-17 |
| 收藏页与历史页选择模式的模拟器走查（iPhone 18 Pro / iOS 27.0，Debug 构建，演示模式）：收藏页标题行只有「选择」、进入后标题「已选择 N 部」+「完成」、筛选变淡、勾选框与选中浅蓝底、底栏换操作栏且未选时按钮禁用；全选变全不选；批量取消 2 部弹「保留 / 取消收藏」确认框、确认后退出选择模式且无撤销提示；左滑一滑到底只露出按钮不删除；历史页长按「选择多项」预选该条、继续卡片收回列表、连同继续条目一起批量删除后剩余条目成为新的继续卡片；空筛选下「选择」变灰。深色与锁定时退出选择模式未走查 | 未编号 | required | approved | implemented | simulator-passed | 6a702af | 2026-10-17 |
| 漫画详情与章节页重设计：漫画类型色淡底头部（封面 + 标题 / 作者 / 徽章 / 更新行 / 来源行）、右上收藏、继续卡片（上次页面缩略图、「13 / 45 页」与进度条）或「从第 1 话开始读」按钮、章节目录按标题形状选三列网格或行列表、≥ 60 章分段芯片滚到段首、按作品读全部章节历史做已读与上次读到标记、历史表追加 `pageCount`、受限与失败提示换页内横幅；向 fwq 提四条生成覆盖需求（九项裁定全取 A） | 未编号 | required | approved | implemented | not-run | a303af5 | 2026-10-08 |
| 漫画详情与章节页重设计的模拟器走查（真实登录账号，めちゃコミック）：淡底头部与列表标题优先、更新行是类型标签、「从第 1 话开始读」、行列表「1-1」编号柱、第 9 话起小锁、开一章回来后继续卡片「6 / 58 页」与进度条、已读 1 与上次读到竖条、正序 / 倒序切换、贴顶分区头停在固定按钮下、受限横幅在分区头里出现且「登录」打开来源登录页、右上收藏实心、深色；三列网格、分段芯片、作者 / 徽章 / 标签 / 日期、没有章节与取失败态未走到（线上只有一条漫画来源，没有纯编号目录与 60 章以上的作品） | 未编号 | required | approved | implemented | simulator-passed | a303af5 | 2026-10-08 |
| 漫画详情分段芯片的滚动锚点按分区头高度换算（合同原第十四节曾记为已知出入、现只在本行：锚点 `.top` 让段首两行压在贴顶分区头下；照站点书详情 `segmentScrollAnchor` 同一做法；按 AGENTS 未 build，未在模拟器看过） | 未编号 | required | approved | implemented | not-run | 2f37a46 | 2026-10-10 |
| 库页漫画库重设计：三列封面墙（封面圆角 10、标题两行 + 最新话一行类型色）、读过的作品封面左下压「读到 4-2」进度角标、只在已收藏时压小爱心、长按菜单加「继续读」、「上次读到」瓷砖（按来源读全部漫画章节历史的只读查询，一次读供瓷砖与角标）、骨架按类型三列、空状态插画 `EmptyStateLibraryComic`；删漫画卡片的 `libraryTitleText` 与写死的蓝紫色（七项裁定全取 A） | 未编号 | required | approved | implemented | not-run | fa57f00 | 2026-10-09 |
| 库页漫画库重设计的模拟器走查（めちゃコミック）：「上次读到」瓷砖（4-2 真夜中の逢瀬 · 6 / 58 页、进度条、时刻）、三列封面墙与「读到 4-2」角标、已收藏小爱心、最新话类型色一行、长按卡片「打开 / 继续读 · 4-2 / 取消收藏」且「继续读」直接进阅读器、从阅读器回来瓷砖时刻刷新、长按瓷砖「继续读 / 打开作品」且「打开作品」进详情（收藏与继续卡片对得上）、深色、底栏为系统原样；骨架、空状态插画、分类芯片、「打开作品」的反解路径、视频库回归未走到（线上只有一条漫画来源、模拟器上没有视频来源） | 未编号 | required | approved | implemented | simulator-passed | fa57f00 | 2026-10-09 |
| 库页书籍库重设计：单列书脊行（封面 60×80 带书脊线、书名两行、「最新 · 原文」、「读到 · 章节名」、行尾已收藏爱心、分隔线）、整站有声按 reader 规则 `contentType` 判（眉行「有声书」、封面耳机、「听到 / 上次听到 / 继续听」措辞）、长按「继续读 / 继续听」直接进阅读器、「上次读到」瓷砖（按来源读全部读书历史 + 瓷砖那一本的 `totalProgression` 进度条）、骨架书脊行形态、空状态插画 `EmptyStateLibraryBook`；删旧卡片与 `libraryTitleText`（十项裁定全取 A） | 未编号 | required | approved | implemented | not-run | a045eab | 2026-10-09 |
| 库页书籍库重设计的模拟器走查（小說狂人 czbooks.net，从目录加）：眉行「书籍 · 主机名」绿色、20 个分类芯片、搜索 + 账号按钮、书脊行（占位封面与真封面都带书脊线、「最新 · 原文」、分隔线）、读一章回来后「上次读到」瓷砖（章节名原文、全书进度条、时刻）与行的「读到 · 第3章 佛祖舍利」、长按行「打开 / 继续读 · 章节名 / 收藏」且收藏后行尾实心爱心、长按瓷砖「继续读 / 打开作品」且「继续读」直接进阅读器、从阅读器回来瓷砖时刻刷新、切分类瓷砖照留、深色、漫画库回归、底栏为系统原样；骨架（切分类太快没抓到）、空状态插画、整站有声（线上没有有声来源）、失败态未走到 | 未编号 | required | approved | implemented | simulator-passed | a045eab | 2026-10-09 |
| 书籍库最新章一行去重前缀（2026-10-11 小說狂人 build 19 真机显示「最新 · 最新: 第1200章」→ 用户裁定 App 侧处理）：`BookLibraryRowView.latestLineText`——原文以「最新」开头时照原文显示、否则「最新 · 原文」；设计书 Library-Book-Page 第 145 行改正归属（fwq `BC-LIST-128`：规则照站点原文交付，App 只截断不改内容）。「更新至」等其它说法照旧叠前缀，量到再议；待下次打包后真机看 | 未编号 | required | approved | implemented | not-run | c2ef68f | 2026-10-11 |
| 站点书详情页重设计：页面底色头部（封面 72×96 带书脊线、书名、作者有才出、来源 · 分类、章数 / 有声书章数）、右上收藏（注入收藏用例）、继续卡片（章名 · 全书 % · 时刻 + 进度条，有声书写 `t=` 时间点）或「从第 1 章开始读 / 听」、简介透传后有才出、贴顶分区头 + 正序倒序 + ≥ 60 章分段芯片、编号柱行列表（解不出整行标题）、上次读到竖条与行尾章内进度、之前的行变淡、续读章先按读书历史 `chapterURL` 对、页内横幅 + 重试 / 登录、骨架与没有章节；`ComicChapterTitleParser` 认中文数字；装配器透传 `description`（十三项裁定全取 A） | 未编号 | required | approved | implemented | not-run | 6ba8846 | 2026-10-09 |
| 站点书详情页重设计的模拟器走查（小說狂人 czbooks.net）：页面底色头部（占位封面带书脊线、书名、来源 · 分类、「1,297 章」）、固定返回与收藏（点了实心、回库页对得上）、有历史的书继续卡片「第3章 佛祖舍利 · 全书 刚开始 · 时刻」、贴顶分区头 + 正序 / 倒序（芯片跟着反过来）+ 分段芯片（点了段首落在分区头下）、编号柱行列表与上次读到竖条 + 「读到 N%」、之前的行变淡、没读过的书「开始读 · 章名」、点行带章节进阅读器、回来后续读章 / 章内进度 / 继续卡片「全书 10%」刷新、继续卡片不带章节回到上次翻到的位置、深色；有声书、失败与登录横幅、没有章节、简介未走到（线上没有有声来源、规则不给简介） | 未编号 | required | approved | implemented | simulator-passed | 6ba8846 | 2026-10-09 |
| 来源内搜索页重设计：隐藏系统导航栏，自绘眉行（类型图标 + 「类型 · 来源名」）+ 「搜索」+ 40pt 圆形关闭；高 48 卡片底搜索框（聚焦 1.5pt 类型色描边、清空叉、键盘搜索键提交、提交收键盘）；结果眉行「“关键词” · N 个结果」（提交时定格的关键词）；结果区 `LibraryContentView` 按 kind 原样复用；未搜索 / 无结果用插画 `EmptyStateSearch` 顶对齐、搜索中按 kind 骨架、失败警示横幅 + 重试（登录墙且来源有登录页多「登录」，登录后自动重搜）；`performSearch` 可取消；接 `searchNextPage` / `loadNextSearchPage`；关闭再打开保留状态、换来源 `clearSearch()`（十四项裁定全取 A） | 未编号 | required | approved | implemented | not-run | 25f754b | 2026-10-09 |
| 来源内搜索页重设计的模拟器走查（小說狂人 czbooks.net，iPhone 18 Pro / iOS 27.0）：眉行「书籍 · 小說狂人 · 玄幻奇幻」青绿图标、「搜索」+ 圆形关闭、进页聚焦且搜索框青绿描边、占位「搜索 来源名」、插画 + 两行说明顶对齐、有字出清空叉、回车提交后描边消失、结果眉行「“100” · 40 个结果」、书脊行结果、点行推入站点书详情（导航栏仍隐藏）再返回结果保留、滚到底没有分页脚、关闭再打开结果保留且不弹键盘、清空回未搜索态并重新聚焦、深色（结果与未搜索）；搜索中骨架（请求太快没抓到）、无结果（czbooks 对任意关键词都回 40 条）、失败 / 登录横幅、分页脚、视频与漫画来源的结果版式未走到；模拟器软件键盘被硬件键盘顶掉、工具不能输入中文，关键词用的是数字与字母 | 未编号 | required | approved | implemented | simulator-passed | 25f754b | 2026-10-09 |
| 规则目录页打开时「我的生成」有条目就优先落在「我的生成」（打开时按已有数据定段、首次拉取完成后再定一次、用户点过分段就不再改） | 未编号 | required | approved | implemented | not-run | 26d1b3e | 2026-10-09 |
| 规则目录「推荐」改名「发现」：上方「站点示例」卡片行组列表（Release 与 Debug 都有，只取服务端标为 `section=example` 的条目，经 fwq 生成后配置，不建演示站）；Debug 构建下方另有「内部测试」分区，沿用原「推荐」类型横幅 + 横滑卡片版式，取 `section=internal` 的原预置站点（服务端只返回给白名单账号）；没有 `section` 的条目不展示；用户分享不在本版（不显示分享者、「···」菜单举报与屏蔽、上线前补齐 UGC 合规与年龄分级） | 未编号 | required | approved | implemented | not-run | bd9a497 | 2026-10-12 |
| 我的生成「删一条失败记录又冒一条」：App 侧删失败记录时把同一入口的全部失败一起软删除（`SourcesViewModel.hideOutcomes`）；PortalCore `OUTCOME_LIMIT` 20 → 200 并补测试（服务端那半在 PortalCore 仓） | 未编号 | required | approved | implemented | not-run | 26d1b3e | 2026-10-09 |
| App 侧显示每次生成的 `aiTokens` / `cloudCost`（PortalCore 自 9827e30 起推送负载与 `/outcomes` 每条都带这两个数，App 现版本忽略未知字段）——2026-10-11 裁定不显示：用户付的是固定价 coin，这两个数是 Provider 用量与云端实扣（普通档 `cloudCost` 为 null），不改变用户任何决定，且 `cloudCost` 是经营侧成本不宜面向用户；重开条件：定价改为按 token 或按实际成本计费，或失败记录要给用户「试了多少」的诊断说明（届时只展示 `aiTokens`） | 未编号 | rejected | superseded | not-started | not-run | f691278 | 2026-10-11 |
| 有声书播放页重设计：整页沉浸深色（播放器功能性例外，局部设深色环境）+ 封面取色流动背景（径向渐变色块只动位移与缩放、后台与减弱动态效果时停）、毛玻璃返回与目录、方形封面（无封面为书籍深色色块 + 耳机）、眉行「第 N / M 集」+ 波形、集名 + 书名、自绘进度条、−10 / 上一集 / 72pt 白色播放键 / 下一集 / +30、倍速五档全局记忆、目录 sheet（卡片行组、当前集青绿、>100 集分段芯片、无书签）、打开中骨架、打开失败下拉重试、听完最后一集；单集音频失效（404 / 403 / 410 或播放页解不出）与没加载出来的一行横条 +「下一集」/「重试」，不自动跳（fwq `APP-MEMO-043`）；有声书打开时不再按章计广告分；锁屏补封面（第 1–6、9–11 项取 A，第 7、8 项取 C，第 1 项看画布后改沉浸深色） | 未编号 | required | approved | implemented | not-run | 4a83331 | 2026-10-20 |
| 有声书播放页重设计的模拟器走查（iPhone 18 Pro / iOS 27，Loyal Books《Tom Sawyer》《The Odyssey》）：打开中骨架、封面取色背景（两本不同）、状态栏随页面深浅、眉行与波形、倍速五档与跨书 / 重开记忆、+30、拖动、上下集与首末集禁用、目录 sheet、听完最后一集；临时注入（未提交）验已失效横条（真实 404）、没加载出来横条与重试恢复、从失败的集换集。走查中修了三处：换集先记请求的集序号、重试新建 AudioNavigator、取色改取最鲜艳的簇；28 个相关测试通过。中文无封面站点、真实 leting8 死链、广告计分、锁屏封面与线控未走到 | 未编号 | required | approved | implemented | simulator-passed | 3f451f3 | 2026-10-20 |
| 品牌等待标记：不做全局网络请求 HUD（`BCA-UI-007`）；`BrandWaitingMark` 圆形墨青底板 #0E1D25 + 海报帧 + 静音循环视频（即梦 4 秒 288×288 HEVC、无音轨，复用启动视频播放器的静音模式、不碰音频会话），减弱动态效果显示海报帧、素材缺失退回系统转圈；删除账号进度遮罩换 96pt、iCloud 首次恢复卡换 56pt 并去掉小转圈；冷启动建库段换 LaunchSplash 静图，启动视频不动；网址输入页不放（八项全取 A）。| `BCA-UI-007` | required | approved | implemented | not-run | 854a09e | 2026-10-20 |
| 品牌等待标记的 build 与模拟器走查（iPhone 18 Pro / iOS 27，XcodeGen 后 build 通过、新文件无新增警告，包内有 brand-waiting.mp4 与 BrandWaitingPoster）：冷启动录屏逐帧看系统启动屏 → 建库段 → 启动视频是同一张图、无白底帧；临时注入（DEBUG 启动参数，测完撤掉未提交）看 iCloud 首次恢复卡两态浅 / 深色、标记在播放、卡片下拉照常；删除账号遮罩浅 / 深色、96pt 标记在播放；减弱动态效果只显示海报帧。走查中修了一处：删除账号这类推入页回前台时 scenePhase 不刷新回 active，标记停在暂停帧——改为播放器监听 App 活跃通知暂停与续播，修正后回前台续播。其他 App 放音乐时不被打断、真机未走；深色下墨青圆在深灰卡片上边界偏弱（观察项）。| `BCA-UI-007` | required | approved | implemented | simulator-passed | 854a09e | 2026-10-20 |
| 占位图收敛：影视详情海报改用 `VideoListPlaceholder`、漫画详情封面改用 `ComicListPlaceholder`，删掉写实比例的 VideoDetailPlaceholder 与 ComicDetailPlaceholder；`BookCoverPlaceholder` 换成 Q 版场景图（戴耳机、抱发光的书站在暖色书架前，216×288 无损，即梦 Seedream 5.0 Pro 3:4 四选一），书籍列表、详情、收藏与历史共用；预算声明同步（五项全取 A） | 未编号 | required | approved | implemented | not-run | 2fb6cb1 | 2026-10-20 |
| 漫画详情 `attributes` 接线：Core 漫画详情解析产出 `SourceDetailAttribute`、Runtime `ComicSourceRuntimeMapper` 构造 `SourceDetailMetadata` 时透传（等 fwq 量到有站点需要再做；合同 Comic-Detail 第二节） | 未编号 | optional | draft | not-started | not-run | d23f431 | 2026-10-20 |
| 影视详情「看过的全部集」：每集一行的新表 + 云同步范围判断（合同 Video-Detail 第九节候选） | 未编号 | optional | draft | not-started | not-run | d23f431 | 2026-10-20 |
| 漫画详情「全部标记已读 / 清除记录」：进云同步范围（合同 Comic-Detail 第九节候选） | 未编号 | optional | draft | not-started | not-run | d23f431 | 2026-10-20 |
| 书类章节 `order`：Core 读、Runtime `loadDetail` 不带也不排序；需求二并入 fwq「书类章节按列写、按行读」记账，两端都不做，同形站多了再两端一起排期 | 未编号 | optional | draft | not-started | not-run | 6ba8846 | 2026-10-10 |

## 3. 影视线运行期

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 运行期广告过滤承接规则匹配结果（App 侧对规则匹配到的候选执行过滤） | `APP-MEMO-008` | required | approved | implemented | full-suite-passed | ff58d6a | 2026-08-29 |
| jable.tv M3U8 播放规则的抽取根因（结论已由 fwq `BC-PLAYBACK-049` 承接） | `BC-PLAYBACK-049` | required | superseded | not-started | not-run | 4a3814b | 2026-08-21 |
| 直接请求收到挑战页时回退 WebView 再取一次（toonily 重生成后规则不带 `needsWebView`，真机三部作品打不开：手机出口直接请求章节页 403 Cloudflare 挑战、服务器出口 200；`DefaultPageLoader.loadContent` 捕获 `antiBot` 后走 `renderedPageContentLoader`，其它错误不回退；fwq `APP-MEMO-026`） | `BCA-RUNTIME-005` | required | approved | implemented | targeted-passed | 9f328d0 | 2026-10-06 |
| WebView 过挑战后把站点 Cookie 回写系统存储 + 书类封面请求带上来源请求配置（`BCA-RUNTIME-005` 2026-10-07 补充两处；xbanxia 真机封面全失败：列表经 WebView 过 Cloudflare，封面请求 `hasCookie=false`、图床回挑战页；第一处上线后复验仍失败，查出书类封面请求配置为空、Cookie 策略缺省不带系统 Cookie；第三处：回写的 `cf_clearance` 按图床地址取不回，改为只用公开属性重建再写入；用户「修，现在实施」，真机确认封面显示） | `BCA-RUNTIME-005` | required | approved | implemented | device-passed | 11c4949 | 2026-10-07 |
| 列表分页页码按 `startPage + N − 1` 代入（0 起页码站 rouman5 / 3kor；fwq `BC-LIST-124` / `APP-MEMO-027`）：Core `PaginationRule.startPage` 与 `sitePageNumber(forPage:)`、影视 / 漫画 / 书三处代入点、目录请求 `features=startPage` 能力声明；Core 3 例 + Runtime 24 例过、App 构建过，未发版 | `BCA-RUNTIME-006` | required | approved | implemented | targeted-passed | 587a99c | 2026-10-06 |
| 站点按状态码拒绝不再报成「规则解析出错」（xjortho 拦桌面 UA 返回 403，正文被当成列表页解析；fwq `MEMO-App-请求被拒显示成规则解析出错`）：直接请求最终状态码 ≥ 400 时先认挑战页、其余抛 `RuleExecutionError.httpStatus`（Domain `d1d5dac`），分类器按状态码四类文案、诊断记 `network`；`loadData` 与 WebView 通道不在范围；用例已写（7 例），四道代码闸门过，未发版 | `BCA-RUNTIME-007` | required | approved | implemented | full-suite-passed | 07a0231 | 2026-10-10 |
| 搜索关键词恰为作品全名时站点直跳作品页、App 显示「没有结果」（fwq `BC-SEARCH-022` ⑤ / `APP-MEMO-032`；piaotia「龙藏」；fwq 量面 5 主机全部交付了搜索：sto55、piaotia、uukanshu、23qb、mangakatana）：书 / 漫画搜索第 1 页 0 条且取页发生过跳转时，落地地址按作品页规则加载，取到标题与至少 1 章即当一条结果（Runtime `ae9a7f0`）；书在落地文档上直接解析不重取、`loadDetail` 逐字不变，漫画重取一次；Runtime `swift test` 32 例过（新增 4 例，书一路），漫画一路无固定输入，四道代码闸门过，未发版 | `BCA-RUNTIME-008` | required | approved | implemented | targeted-passed | ae9a7f0 | 2026-10-11 |
| 书类目录自身分页逐页取（fwq `BC-BOOK-061` / `APP-MEMO-033`；读书需求文档需求五后半，用户 10-11「批准，两端同批」、上限 100）：Core `BookDetailRule.chapterPagination` 与校验（Core `491b28f`，swift test 282 例过）、Runtime 从第 2 页起按相对模板逐页取、无新章节 / 失败 / 到上限即停（Runtime `d08756b`，swift test 37 例过、新增 5 例）；搜索直跳兜底不翻页；四道代码闸门过；引擎已部署，未发版 | `BCA-RUNTIME-009` | required | approved | implemented | targeted-passed | d08756b | 2026-10-11 |
| 运行期广告过滤词表下发：词表随 Runtime 包发布、新广告形态要发版，是否改为服务端下发（合同 RuntimeAdFilter 第五节） | `APP-MEMO-008` | optional | draft | not-started | not-run | d23f431 | 2026-10-20 |
| Runtime 四笔运行期语义变更的 App 侧引用点：播放页型有声章节（fwq `APP-MEMO-035`）、整站单篇补一章（fwq `BC-BOOK-066`）、「仍在本章」认路径下页码续页（fwq `APP-MEMO-038`）、播放规则 `media` 只声明 `documentURL` 时不当网页取（fwq `BC-PLAYBACK-066`）；前三条已写进 Book-Kind-Wiring 第三 / 十三节与 RuleExecutionSemantics `BCA-RUNTIME-008`，状态在 fwq STATUS | 未编号 | required | approved | implemented | targeted-passed | 1a0f714 | 2026-10-17 |

## 4. 身份与同步

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 身份边界切换到 Sign in with Apple 与后端生成的 AppUser UUID | 未编号 | required | approved | implemented | full-suite-passed | eeb288e | 2026-07-28 |
| CloudKit 上传前的安全门禁——记录大小预算（900 KB / 800 KB / 8 KB）、URL userinfo、本地 account scope 泄漏：`CloudSyncPayloadSecurityValidator` 已实施并接线 | `BCA-SYNC-008` | required | approved | implemented | full-suite-passed | bed4ab3 | 2026-07-25 |
| CloudKit 门禁的 Header 名称拦截与 `context.*` / Request Body / `keyHex` / `ivHex` / constant value 字面量扫描——实现有意收窄为「不推测站点规则常量是否敏感」，13 例固定输入钉住该取值 | `BCA-SYNC-008` | optional | superseded | not-started | full-suite-passed | bed4ab3 | 2026-07-25 |
| Phase0 审计的安全结论已提升为 C：排除数据、冲突与删除、凭据引用三条成 `BCA-SYNC-009` ~ `011`，未实施的全面扫描部分显式声明为有意收窄 | `BCA-SYNC-009` `BCA-SYNC-010` `BCA-SYNC-011` | required | approved | implemented | static-audit-passed | 69779bb | 2026-09-19 |
| RSS 整体下线：删功能、迁移 v6 清存量、同步跳过 rss、书籍收藏改记 book | 未编号 | required | approved | implemented | full-suite-passed | f263274 | 2026-09-16 |
| 删除来源连带删除历史与收藏：用户删除时删三张历史表、给收藏写删除标记并入队；iCloud 应用远端删除时删本机历史并清空当前选择；删除后底部可撤销并原样写回；删除与撤销后刷新历史、收藏与库页；底部文案改写 | `BCA-DB-004` `BCA-DB-005` | required | superseded | reverted | full-suite-passed | c2b2437 | 2026-10-17 |
| 删除来源连带删除的模拟器走查：左滑删除非内置来源与长按删除内置来源，历史、收藏、库页爱心随删除消失、随撤销回来，撤销后改回当前来源 | `BCA-DB-004` `BCA-DB-005` | required | superseded | reverted | simulator-passed | c2b2437 | 2026-10-17 |
| 删除来源时保留历史与收藏（用户 2026-10-17 裁定，取代连带删除）：用户删除与应用 iCloud 远端删除都只软删来源、清空库的当前选择，三张历史表与收藏不动、收藏不入队；被删来源的条目照旧用快照打开（来源位置可被绕过，用户接受）；撤销只写回来源与库状态；来源页底部说明三语；RootView 只重新载入历史与收藏；仓储与远端删除测试、来源页 ViewModel 测试断言改为保留 | `BCA-DB-004` `BCA-DB-005` | required | approved | implemented | targeted-passed | c44934a | 2026-10-17 |
| 续看位置同步到 iCloud：每部作品一条续看记录（云端 `HistoryEntry` 21 个字段，已部署到 Production）、本机账本对比找改动、来源先于历史下载、删除与恢复、退到后台时同步、云同步页第三行改为作品数 | `BCA-SYNC-009` | required | approved | implemented | full-suite-passed | 7102bba | 2026-10-04 |
| 续看位置同步的模拟器走查（真实账号，Development 环境，单台设备）：迁移后正常启动、新增来源并产生一条视频历史、退到后台触发同步并上传、云同步页第三行显示作品数、来源已删除的历史不计入也不上传、删除历史后退到后台上传删除标记；两台设备互相接续与书的阅读位置未走到 | `BCA-SYNC-009` | required | approved | implemented | simulator-passed | 7102bba | 2026-10-04 |
| 删除账号 App 侧（审核指南 5.1.1(v)；服务端 PortalCore 设计稿第 12 节第 5 步）：设置页入口与说明页、重新验证 Apple 后调删号接口、本机与 iCloud 清理、换访客身份、待清 iCloud 标记、凭据状态监听、三语文案 | 未编号 | required | pending-review | implemented | targeted-passed | fda3bb6 | 2026-10-15 |
| 删号后恢复购买：恢复路径按 appAccountToken 分批、外来 token 遇 accountMismatch 跳过，购买页已拥有判断放宽（删除账号设计第九节，D4 在 App 侧的落点） | 未编号 | required | pending-review | implemented | targeted-passed | a06be2d | 2026-10-15 |
| 删号后恢复购买的真机走查（iPhone 15，iOS 26.7.1，Xcode 直装、沙盒账户）：被删账号名下的 Sandbox 交易单独成批提交，服务端认领到当前账号，权益快照站点位置上限 2，界面显示已恢复且不提示属于别的账号 | 未编号 | required | approved | implemented | device-passed | b0e2a0d | 2026-10-15 |
| 购买页：StoreKit 拥有但未被当前账号认领的购买显示「需要恢复」而非「已购买」（删除账号设计第 9.2 节） | 未编号 | required | pending-review | implemented | targeted-passed | b0e2a0d | 2026-10-15 |
| 账号接口回 401 时强制刷新会话：刷新被拒即回到未登录并刷新设置页，刷新成功则重试一次（删除账号设计第 7.1 节，另一台设备上的已删账号） | 未编号 | required | pending-review | implemented | targeted-passed | dda4378 | 2026-10-15 |
| 删除账号的模拟器走查（iPhone 18 Pro，iOS 27.0，生产服务器真实账号）：入口、说明页显示余额、居中确认框、Apple 重新验证、不可取消遮罩、完成页；服务端账号与个人数据清空、254 个任务转挂占位用户、Apple 授权撤销成功；本机换访客身份、来源清空；iCloud 不可用时留待清标记并在启动与回到前台重试；重新登录为新账号且不发注册赠送；凭据检查不再误退。恢复购买因模拟器沙盒登录被系统拒绝未走到 | 未编号 | required | approved | implemented | simulator-passed | a8d9ccb | 2026-10-15 |
| 删除账号页重设计（设计稿 2026-10-16 用户确认，删除账号设计第三、四、八节）：页顶删除色圆形图标 + 大标题；会删除 / 会保留 / 删除前请留意三张卡（32pt 图标块 + 标题 + 说明，coin 行尾删除色大数字），新增撤销 Apple 授权与「12 个月内同一 Apple ID 再登录不再送新账号 coin」两行；「接下来」三步事先说明 Apple 验证；「继续删除」+「保留账号」；进度遮罩补一句说明；完成页改为结果清单（账号与 coin、Apple 授权、本机、iCloud 四行，按 AccountDeletionOutcome 显示完成或附说明）；三语文案 | 未编号 | required | approved | implemented | not-run | 4131f24 | 2026-10-16 |
| 删除账号页重设计的模拟器走查（iPhone 18 Pro / iOS 27.0，Debug 构建，生产服务器已登录账号）：设置页入口、说明页简体浅色与繁体深色（页顶图标与大标题、三张卡、coin 行尾显示服务端余额 8800、接下来三步、继续删除 / 保留账号）、居中确认框文案、保留账号返回设置页；未走 Apple 验证与真删，删除中遮罩与完成页未走查 | 未编号 | required | approved | implemented | simulator-passed | f84e72c | 2026-10-16 |
| 设置页「关于」加「隐私权政策」行（审核指南 5.1.1(i)）：图标 SettingsPrivacy（SF Symbol hand.raised.fill 按设置页剪影规格栅格化、登记资产预算），点开用系统浏览器打开 https://anyportal.online/privacy（PortalCore a77d69f 的 `GET /privacy`）；三语文案 | 未编号 | required | approved | implemented | not-run | 3fb8793 | 2026-10-16 |
| 设置页「隐私与诊断」加「发送使用统计」开关：绑定 AppAnalytics 已有的 settings.analyticsEnabled，关闭即 Firebase Analytics 停收、log() 跳过，与崩溃诊断分开（用户 2026-10-16 裁定单独一行）；图标 SettingsAnalytics；三语文案；隐私权政策同步（PortalCore） | 未编号 | required | approved | implemented | simulator-passed | 2593f6e | 2026-10-16 |
| 收藏与历史的面容 ID 锁定（设计稿 2026-10-17 用户确认）：设置页「安全」分组一行开关（标题与图标随面容 ID / 触控 ID / Optic ID / 只有密码变，没有锁屏密码时禁用），打开与关闭都先验证；收藏页与历史页共用锁定态盖在整页之上，两页共用解锁状态，切进来与回到前台自动拉起验证，非活跃时盖上、进入后台重新锁定；图标 SettingsFaceID / SettingsTouchID / SettingsOpticID / SettingsPasscode 登记资产预算；面容 ID 用途说明与三语文案 | 未编号 | required | approved | implemented | not-run | a3750c6 | 2026-10-17 |
| 收藏与历史锁定的模拟器走查（iPhone 18 Pro / iOS 27.0，Debug 构建）：未录入面容 ID 时为「密码锁定」，打开开关弹系统密码界面、取消后开关不变；录入后为「面容 ID 锁定」，打开与关闭都先验证；打开后直接进收藏；回桌面再回来重新锁定并自动拉起面容 ID；不匹配后取消停在锁定态、显示警示小字且不再循环拉起；点按钮解锁后切到历史不再验证；锁着时切到库不拉起、切到收藏自动拉起；多任务切换器缩略图为锁定态、从切换器回来不要求验证；关闭后回到前台两页直接可看；历史锁定态与设置分组深色。没有锁屏密码的禁用态模拟器造不出来，未走查；两页在该账号下都为空，未看有列表时的遮盖 | 未编号 | required | approved | implemented | simulator-passed | a3750c6 | 2026-10-17 |

## 5. 文档架构迁移

本节全部行已到终态，2026-10-20 按 `BCA-DOC-016` 整节退休，原样见 [history/status-log.md](history/status-log.md)「已结案」节。

## 6. 代码审计（2026-09-18）

原始清单与逐项论证在 [history/2026-09-18-code-audit.md](history/2026-09-18-code-audit.md) 第 5 节。
本节只承载状态：**要判断「今天还剩什么」看本节即可，不必读原文**。
「前提被测量推翻」的条目记为 `决策=rejected` + `验证=targeted-passed`——测量做过且是结论的依据，
条目本身不实施。

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 阶段 0 闸门基线（F0-1~4）：四包严格并发、边界脚本 import 写法与三个引用方向、`print`/`try!` 扩到四包 | `BCA-ARCH-004` | required | approved | implemented | static-audit-passed | 1febbf1 | 2026-09-18 |
| 阶段 1 清零 37 条编译器警告（F1-1~11）：App 与测试目标均 0 条 | `BCA-ARCH-007` | required | approved | implemented | static-audit-passed | 3af597e | 2026-09-18 |
| F2-1 正则缓存、F2-2 按目标宽度降采样解码成为共享 pipeline 的通用机制 | 未编号 | required | approved | implemented | static-audit-passed | 305895f | 2026-09-18 |
| F2-3 前半与 F2-4：封面请求按标识变化只构造一次，按测得单元格尺寸声明 thumbnail 解码 | 未编号 | required | approved | implemented | static-audit-passed | 718ea07 | 2026-09-18 |
| F2-3 后半：显式 `ImagePrefetcher` 预取——不做：`LazyVGrid` 本就提前实例化下一屏单元格、`LazyImage` 随之开始加载，显式预取的增量收益没有测到 | 未编号 | rejected | superseded | not-started | not-run | 718ea07 | 2026-09-19 |
| F2-5 进列表先读后写与来源配置解码缓存、F2-6 读书线读库经 actor 离开主线程 | 未编号 | required | approved | implemented | not-run | 0baf3e3 | 2026-09-18 |
| F2-7 WebView 稳定判定改 MutationObserver 静默窗口——前提被固定输入测量推翻，条目关闭 | 未编号 | rejected | superseded | not-started | targeted-passed | 3286951 | 2026-09-18 |
| F2-8 发现分析器传 `Document` 不传 `html`、F2-12/F2-13 历史批量删除合并写事务 | 未编号 | required | approved | implemented | static-audit-passed | 5d5e421 | 2026-09-18 |
| F2-9 `MobileAds.start()` 延后到引导完成——**已实施后回退**：必须早于 `FirebaseApp.configure`，否则覆盖 Crashlytics 信号处理器 | 未编号 | required | superseded | reverted | targeted-passed | 810c9ce | 2026-09-18 |
| F2-10 预检复用 WKWebView 与数据存储——判定不动：每次取样各自一个非持久存储是隔离前提 | 未编号 | rejected | approved | not-started | not-run | 5d5e421 | 2026-09-18 |
| F2-11 资产瘦身：占位图砍冗余 scale 槽位 + 按渲染宽度选有损，内购背景转 HEVC | `BCA-BUILD-006` | required | approved | implemented | targeted-passed | 7ac3d47 | 2026-09-18 |
| 阶段 3 F3-3 Core 拆「规则模型 / 解析」两 target、F3-4 退役候选合同别名 | `BCA-ARCH-002` | required | approved | implemented | static-audit-passed | 473e8c7 | 2026-09-18 |
| 阶段 3 F3-1 包侧加 `Tests/`——前提被测量否定：104 个 App 测试文件里 101 个 `@testable import` App | 未编号 | rejected | superseded | not-started | targeted-passed | 473e8c7 | 2026-09-18 |
| 阶段 3 F3-2 `DefaultRuleExtractionEngine` 的默认构造改注入——判定不再需要：与解析器同在一个 target | 未编号 | rejected | superseded | not-started | not-run | 473e8c7 | 2026-09-18 |
| 引导失败诊断：错误类型自己声明可安全记录的摘要，Keychain 的 `OSStatus` 可见 | `BCA-SYNC-001` | required | approved | implemented | static-audit-passed | 367da97 | 2026-09-18 |
| 边界豁免收敛：`Features→Infrastructure` 七条与 `Shared` 两个方向清掉，豁免清单降到 1 条 | `BCA-BUILD-005` | required | approved | implemented | static-audit-passed | b1c60e7 | 2026-09-18 |
| WebView 就绪选择器：加载器按「规则要提取的内容到了没」提前返回，等待 3438 ms → 314 ms | `APP-MEMO-016` | required | approved | implemented | device-passed | 54e2df3 | 2026-09-18 |
| Swift 6 语言模式：App 与四个包切换，并加闸门把「警告为零」固化成编译错误 | `BCA-ARCH-007` | required | approved | implemented | static-audit-passed | 2f769ae | 2026-09-18 |
| 封面请求重复构造——代价测量否掉：重复的只是请求构造，改发布时序要动两个 ViewModel，条目关闭 | 未编号 | rejected | superseded | not-started | targeted-passed | 70b2700 | 2026-09-18 |

## 7. 规则生成入口

本节全部行已到终态，2026-10-10 按 `BCA-DOC-016` 整节退休，原样见 [history/status-log.md](history/status-log.md)「已结案」节。

## 8. 代码复审（2026-10-10）

复审报告与八条裁定见 Claude 文档「BrowseCraft 代码复审报告 2026-10-10」（https://claude.ai/code/artifact/fa99d4cf-3497-46de-94f5-923f89930335）。
检查点为实施提交。

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 开启云同步前的 Portal 登录门禁（关联协调器 + 设置页开关禁用），以及云端记录为本机旧本地 UUID 时用当前账号覆盖的清理路径；用例 3 条 | `BCA-SYNC-004` `BCA-SYNC-010` | required | approved | implemented | full-suite-passed | a6eed01 | 2026-10-10 |
| 缩略图管线缓存键：去掉自定义管线键让内存 / 磁盘键回到带解码尺寸的默认形态，Cookie 只按名进键；用例 1 条 | 未编号 | required | approved | implemented | full-suite-passed | a6eed01 | 2026-10-10 |
| 影视 / 漫画详情已有内容时刷新失败改走横幅；搜索页失败态重开不聚焦；搜索结果带漫画进度角标与整站有声措辞 | 未编号 | required | approved | implemented | full-suite-passed | a6eed01 | 2026-10-10 |
| 规则导入死代码栈（`addRuleSource` 与候选分析）与两个 Discovery 视图删除，装配与测试替身随之收口；临时资源页仍用的 `ComicDiscoveryWebResourceView` 搬到 `Features/History/Details` 保留 | `BCA-UI-003` | required | approved | implemented | full-suite-passed | a6eed01 | 2026-10-10 |
| 三处过期用例跟上已提交的代码：目录请求带 `features=startPage`、视频详情属性带 `key`、v9 后的 schema 快照列序 | `BCA-RUNTIME-006` `BCA-DB-003` | required | approved | implemented | full-suite-passed | a6eed01 | 2026-10-10 |
| 复审 B-2 / B-3：三个历史仓储加按来源与按作品（子查询取每部最近一章）查询，历史页与库页瓷砖不再读全表；三个详情页的收藏与站点书详情的进度 / 历史经 actor 离开主线程（`FavoriteStatePersistenceCoordinator`、`BookDetailPersistenceCoordinator`） | 未编号 | required | approved | implemented | full-suite-passed | 2780b7a | 2026-10-10 |
| 页面缺口：添加来源页未登录提示警示色、书脊列表宽屏页边距 40、书详情失败文案走分类器；影视 / 书 / 漫画详情与库页读屏标签的 11 条裸英文进三语词条 | 未编号 | required | approved | implemented | full-suite-passed | 2780b7a | 2026-10-10 |
| Runtime README 的 `Bundle(for:)` 改为 `Bundle.module`；APIKit README 补三个目录与五条端点 | `BCA-ARCH-006` | required | approved | implemented | static-audit-passed | 2780b7a | 2026-10-10 |
| 复审 B-9 / B-5：七处绕过 `RegularExpressionCache` 的正则（Core 三处、Runtime 两处走缓存；App 漫画标题解析与影视集名改为只编译一次的静态实例）；阅读页 `ReaderPageImageView` 的请求按身份只构造一次，不在 body 里重扫 Cookie | 未编号 | required | approved | implemented | full-suite-passed | 6902c81 | 2026-10-10 |
| 架构清理：14 个成员全不可变的 `@unchecked Sendable` 改 `Sendable`、其余 16 个补「依据」注释；Runtime `BookSourceRuntime` 两处 `try!` 改可选值 + 正则缓存，豁免清单归零；`CoinLedgerViewModel` 从 Application 搬到 Features（工厂改为 Features 侧扩展）；architecture.md 第 1、2、3、4、6、8、9 节与 Core `CoreParsingBoundary` 依赖图回写 | `BCA-ARCH-004` `BCA-ARCH-005` `BCA-BUILD-005` | required | approved | implemented | full-suite-passed | b42c89f | 2026-10-10 |
| Domain 包瘦身：`CatalogSource`、`SourceSnapshot`、`SourceCredentialStoring`、预检取页端口与 `PublicURLChecking` 搬回 App（`Domain/Models/Source`、`Application/Ports/Credentials`、`Application/Ports/Preflight`）；`PreflightAcquiredPage` 因 Runtime 分类器消费、`PreflightPageAcquisitionError` 因 Shared 埋点归类、`Source.accessState` 因 Runtime 工厂门禁而留在内核；复审所称「六个零引用类型」逐个核实均为内核值的字段类型，不删 | 未编号 | required | approved | implemented | full-suite-passed | 74e4fb5 | 2026-10-10 |
| 复审 B-6 / B-7 / B-8：影视详情的线路、当前线路、可见集、等宽网格、上次看的那一集与格子文字，漫画详情的已读数、最近历史与上次读到的章，书详情的上次读到行与已读集合，历史页与收藏页的计数、筛选结果与按天分组，全部改为数据或筛选变化时算一次的存储属性（`didSet` 触发）；改前用真实 ViewModel 加合成数据测得一次渲染 33.4 / 19.2 / 10.1 / 7.0 / 3.4 ms（Debug），改后均低于 0.4 ms | 未编号 | required | approved | implemented | full-suite-passed | 74e4fb5 | 2026-10-10 |
| 复审 B-4：目录跟随先比来源行上的目录规则指纹（v10 迁移加 `catalogRuleFingerprint`），指纹不同才物化校验；比较离开主线程；有更新的条目合成一个写事务、只重读一次来源表；自动跟随不再经 `addCatalogSource`（不碰当前选择、不触发切库页）；迁移用例 2 条、跟随用例补指纹断言 | `BCA-DB-001` `BCA-DB-003` | required | approved | implemented | full-suite-passed | 1d8b079 | 2026-10-10 |
| `BCA-PARSE-006` 补写 fwq `BC-COMIC-147` 例外；StoreKit 适配落点按现状写进 architecture.md 第 9 节 | `BCA-PARSE-006` | required | approved | implemented | static-audit-passed | a6eed01 | 2026-10-10 |
| 复审跨页复制第一组：页内横幅三套收成 `Features/Library/Components/LibraryStateBanner.swift`（失败态：三角 + 「登录」警示色描边 + 「重试」警示色实心；受限态：锁 + 「登录」警示色实心 + 关闭叉；只给文案即库页纯文字横幅；按钮不用类型色），库页、影视 / 漫画 / 书详情、搜索页六处调用，漫画详情自带的横幅与书详情、搜索页各自的 `bannerButton` 删去；同一条历史的时刻写法收成 `LibraryHistoryTimeText`（今天 / 昨天带时刻，更早只写日期，与库页瓷砖同一套），两个详情页删各自的 `DateFormatter`；横幅词条改三页共用 `library_banner_login / retry / dismiss`，删 `comic_detail_restricted_login`、`book_detail_retry`、`comic_detail_banner_dismiss`；六份页面合同同步 | 未编号 | required | approved | implemented | full-suite-passed | a9d5446 | 2026-10-10 |
| 复审剩余文档回写：数据库 README 登记历史同步账本与区域重建清账本；RuleExecutionSemantics 第三节补直接请求通道 302 到 http 升 https（引用点 fwq `BC-BOOK-050`）；AGENTS 与 architecture.md 把目录通道改成实际的 `AddCatalogSourceUseCase`、第 9 节登记 APIKit `PortalCatalogAPI` 零引用待删；漫画详情合同补「按首尾话数推断方向优先于规则声明」与受限横幅位置；规则目录（横幅通栏、添加成功即关闭看不到已添加态、警示色浅深两值）、来源页与收藏页（恢复态独立一页、空状态带位置计数）、添加来源（顺序由页面自持）、影视详情（网格按线路二选一、骨架三条、元数据两行）、视频库（昨天带时刻、顶部按钮阴影、分页脚是推定）、网址输入（检查中收起说明、普通档也有说明、无钱包不出余额、两种蓝）、云同步（`activationIssue == .statusUnavailable` 一行）、书详情（小封面圆角 6）九份页面合同按代码改写；Core 仓 CoreParsingBoundary 第 8 节 RSS 措辞另一笔 | 未编号 | required | approved | implemented | static-audit-passed | 6f90bba | 2026-10-10 |
| 复审合同 3：`BCA-DB-003` 给 v7 / v8 / v9 补「上一正式版本升级」用例（`AppDatabaseUpgradeFixtureMigrationTests` 三条）：v6 → 最新 users 两列 coin 缺省 0 且旧行原样；v7 → 最新账本表建成且为空、主键四列、外键接 users（孤儿行插不进）、漫画历史原样；v8 → 最新漫画历史 `pageCount` 列加上且旧行为 NULL；三条都跑 `foreign_key_check`；旧 schema 插历史行的助手 `insertComicChapterHistoryRowAsOfV8` 按当时的列写 SQL | `BCA-DB-003` | required | approved | implemented | full-suite-passed | 81977a0 | 2026-10-10 |
| 复审 B-10：共享图片管线内存缓存显式上限——`ImageCacheConfigurator.configureSharedPipeline` 给 `ImageCache.shared` 设 costLimit = min(Nuke 缺省, 256 MB)、entryCostLimit 0.2（单张绝对上限约 51 MB 与缺省相同）；先用临时用例在模拟器量过（量完即删）：缺省 costLimit 512 MB，按阅读器目标宽度 1206 解码后普通页 800×1200 成本 3.7 MB、长条 800×6000 成本 18 MB，缺省下 27 张长条 494 MB 常驻，256 MB 下装 69 张普通页或 13 张长条；模拟器进程的 phys_footprint 不随缓存成本涨（四次测量含随机噪声图与强制取位图数据都是 +20 MB 以内），驻留要上真机 Instruments 看；用例 `ImageCacheConfiguratorMemoryLimitTests` 一条；缓存页合同第二节补内存两块的上限 | 未编号 | required | approved | implemented | full-suite-passed | 1dee0f7 | 2026-10-10 |
| 复审两件裁定之一：库页翻页失败走分页脚——`LibraryViewModel.nextPageErrorMessage` 只在 append 模式失败时写、下次触底 / 换来源 / 换用户时清；分页脚第四条词条 `library_pagination_failed`「第 N 页 · 加载失败，再滑到底重试」警示色 + 原因小字（`LibraryPaginationFooterView.failureDetail`，影视网格同一个脚）；库页系统弹框只剩收藏切换失败在用，标题改为来源名；三份库页合同「其余状态」各加一行；用例 `LibraryPaginationFailureTests` 两条 | 未编号 | required | approved | implemented | full-suite-passed | acc1e88 | 2026-10-10 |
| 复审两件裁定之二：目录单条规则解不开逐条跳过——`LoadCatalogSourcesUseCase.catalogSourceData` 对没带密文、密钥不认得、解密或解码失败的条目逐条跳过并记 notice（id、kind、错误码），整表一条都解不开才整表失败；未知 kind 的跳过日志从 debug 升 notice；`BCA-RUNTIME-004` 正文扩写；用例 `LoadCatalogSourcesUndecryptableRuleTests` 两条 | `BCA-RUNTIME-004` | required | approved | implemented | full-suite-passed | acc1e88 | 2026-10-10 |
| 复审「Features 层颜色绕过 `CatalogStyle`」收敛：`CatalogPalette` 新增按角色命名的取值 `onAction` / `onAccent` / `onPrimary` / `plainBackground` / `separator` / `tertiaryText` / `pressedFill` / `pressedScrim` / `shadow` / `cardShadow` / `posterShadow` / `coverScrim` / `coverShade` / `badgeScrim` / `headerScrim` / `onDarkFill`，30 个文件 58 处 `.white` / `.black` / `Color(uiColor:)` 直取改为取调色板（固定深色瓷砖上的半透明白由 14% / 16% / 18% 统一为 16%，其余取值不变）；三个视图删掉只为算 `onAccent` 的 `colorScheme`；功能性颜色在调色板注释里登记为例外（阅读器页面底、播放器黑底、启动动画、调试页、Apple 登录按钮样式、设置页全屏广告位黑底、流光描边两端白光），规则目录合同第三节写明取值规则与例外 | 未编号 | required | approved | implemented | full-suite-passed | 06071f1 | 2026-10-11 |
| 颜色收敛的模拟器走查（iPhone 18 Pro / iOS 27.0，浅色与深色各一遍）：库页书籍库（选中芯片字色、圆按钮阴影、瓷砖进度条轨道、分隔线）、来源页（深色瓷砖徽章、位置条、顶部分段按钮分隔线）、规则目录「我的生成」（蓝底加号白字、地址路径三级灰、进度条、失败卡）、书详情（开始按钮字色、选中分段芯片、封面书脊、圆按钮）；与改前看不出差别。未走到：影视与漫画的库页、详情页与阅读器（线上只有书籍来源）、设置与云同步页 | 未编号 | required | approved | implemented | simulator-passed | 06071f1 | 2026-10-11 |
| 复审跨页复制第二组（纯重构，不改视觉）：分段芯片的分段算法与选中 / 滚动锚点状态机收成 `ChapterSegmentation` / `ChapterSegmentSelection`（书详情点芯片后的放开改为与漫画同样延迟 600 ms）；三个详情页的收藏读写收成 `DetailFavoriteToggling` 协议扩展；简介块、骨架条、相关链接收成 `DetailSynopsisSection` / `DetailSynopsisSkeleton` / `DetailSkeletonBar`；五份 `nonEmpty` 收成 `TrimmedText`；`ComicChapterSegment` 改名 `ChapterSegment`、`ComicDetailRelatedLink` 改名 `DetailRelatedLink`；三份详情合同实现位置登记 | 未编号 | required | approved | implemented | full-suite-passed | 601ddf9 | 2026-10-11 |
| 跨页复制第二组的模拟器走查（iPhone 18 Pro / iOS 27.0，小說狂人「絕對之門」680 章）：点「148–196」滚到第 148 行、段首落在分区头下不被盖住、2 秒后芯片仍选中不被抢回；往回滚芯片依次换到「99–147」「51–98」「1–50」；右上收藏点了实心、再点空心；简介「展开 / 收起」切换。未走到：漫画详情（线上没有漫画来源）、影视详情 | 未编号 | required | approved | implemented | simulator-passed | 601ddf9 | 2026-10-11 |
| 复审跨页复制第三组（视觉组，用户裁定统一取值）：继续卡片 `DetailContinueCard`（圆角 16、缩略图 56×72 圆角 8、标签 `caption` semibold、章名 `headline`、间距 14 / 4）、开始按钮 `DetailStartButton`、固定返回 / 收藏 `DetailTopButtons`（卡片底 + 黑 8% 轻阴影、爱心 20）、贴顶章节分区头 `DetailChapterHeader`（`headline` 主色 + 次级小字、正序 / 倒序胶囊、分段芯片、附加横幅位）、分区头上方底色补铺 `detailPinnedHeaderBackground`；漫画详情与书详情接上，两份合同取值改为统一值 | 未编号 | required | approved | implemented | full-suite-passed | 7b06790 | 2026-10-11 |
| 跨页复制第三组的模拟器走查（iPhone 18 Pro / iOS 27.0，小說狂人）：「絕對之門」没有历史的开始按钮、贴顶分区头（`headline` 标题、正序胶囊、分段芯片）、顶部圆按钮带轻阴影；「都重生了誰還正經創業啊」有历史的继续卡片（56×72 带书脊线小封面、`caption` semibold 标签、`headline` 章名、「全书 10% · 10 月 9 日」、进度条、圆角 16）、已收藏实心爱心。未走到：漫画详情（线上没有漫画来源） | 未编号 | required | approved | implemented | simulator-passed | 7b06790 | 2026-10-11 |
| 复审架构项收尾：APIKit 仓删零引用的 `PortalCatalogAPI`（只带 `kinds=` 不带 `features=` 的请求封装；目录请求由 `AddCatalogSourceUseCase` 直接发），`BrowseCraftSourceCatalog` 纯解码入口保留；APIKit `swift test` 40 例全过；architecture.md 第 9 节撤掉这条已知债务 | `BCA-RUNTIME-006` | required | approved | implemented | static-audit-passed | 7b06790 | 2026-10-11 |
| 规则匹配不到内容时换手机 Safari UA 重做一次并按来源记住（fwq `APP-MEMO-037` / 设计稿第 54 节；huanmengacg 困难档生成成功、真机「规则没有匹配到内容」——站点按 UA 分模板、云端取到手机模板而规则 UA 是桌面）：`SourceUserAgentFallback` + 两条取页路径组头处套用 + 8 个调用点；Domain `ClientUserAgent.mobileSafari`；模拟器构建通过，`SourceUserAgentFallbackTests` 8 例与 `PageContentLoaderTests` 5 例过（iPhone 17 / iOS 27.0）；同日修订：图片配置全部出口跟随来源 UA（书库 / 书籍目录页封面 / 漫画详情与阅读页）；真机待下次打包（huanmengacg） | `BCA-RUNTIME-010` | required | approved | implemented | targeted-passed | aa1675f | 2026-10-13 |
| 图片先按浏览器带当前页面 Referer、失败再不带重试一次（fwq 第七批真机抽验 umh5：mkzcdn 拒外站 Referer；回归面测出 bhtv001 ← kanrenao 反而要求带——单一取舍不行）：`ImageRequestFactory.omitPageReferer` + 封面 / 缩略图尝试序列 + 阅读页重试一次 + 缩略图键区分带不带；`ImageRequestFactoryTests` / `RemoteImageRequestIdentityTests` 14 例过（iOS 27 模拟器）；真机（a777d54）详情页封面先显示列表封面、作品页封面 403 后变占位图——补：三种详情页头部封面以列表封面作备用地址；真机（fc72eba）漫画页回归——重试被 Nuke 合并（合并键不看 imageIdKey）+ 页格 `.id(Bool)` 同 id，改为重试换 cachePolicy、`.id` 挂里层；15 例过；待打包后真机看 umh5 与 bhtv001 | `BCA-RUNTIME-011` | required | approved | implemented | targeted-passed | 54090d2 | 2026-10-15 |
| 来源发现链路与更多方案页死代码删除（埋点审计 2026-10-17 发现：`search_submitted` 挂在两个从未被界面调用的 discover 方法上）：`SourcesViewModel` 两个 discover 方法、`SourceDiscoveryService` 两个 discover 方法与两个用例、扫描器、HTML 发现解析端口与 Core 适配器、两个临时发现条目模型删除，组装根与 ViewModel 测试装配随之收口（`SourcesFeatureFactory` 去掉不再使用的页面内容加载器与网址解析器入参，测试替身 `StubPageContentLoader` 一并删除）；全仓无引用的 `MoreInAppPurchasePlansView` 删除，三语只被它用到的「More Plans」词条删除。`AppAnalytics.logSearchSubmitted` 留给埋点改造搬到来源内搜索 | 未编号 | required | approved | implemented | static-audit-passed | 217fbd8 | 2026-10-17 |

## 9. 埋点全覆盖

设计与裁定见 Claude 文档「BrowseCraft 埋点事件审计与全覆盖设计」（https://claude.ai/artifact/9tKxLWvTiLpAbAta6dCGoe），合同见 [design/Analytics-Events-Design.md](design/Analytics-Events-Design.md)。

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 埋点全覆盖（用户 2026-10-17 裁定全部按推荐、时长分桶加 60_120m / gt_120m）：`AppAnalytics.Event` 重写为 64 个事件（保留或扩参 13、改名 2、新增 49，删 3 个规则导入事件与 `generation_insufficient_coins`），27 个参数与 34 个页面名各带中文注释；取值枚举集中在 `AnalyticsValues.swift`，上报方法按 A–I 分组；页面曝光统一走 `.analyticsScreen(_:)`，Info.plist 关掉 Firebase 自动屏幕报告；来源、目录、生成、库、搜索、登录、详情、阅读、播放、广告、ATT、收藏、历史、锁定、设置、购买、云同步、缓存、删除账号、启动与推送的调用点全部接上；Application 层只改返回值（解锁结果、推送是否弹窗、广告到账轮询、同步结果），不调 `AppAnalytics`；新增域 `OBS` 与 `BCA-OBS-001` ~ `005`，文档闸门加 A13（字典与代码双向一致、注释齐全、调用边界） | `BCA-OBS-001` `BCA-OBS-002` `BCA-OBS-003` `BCA-OBS-004` `BCA-OBS-005` | required | approved | implemented | targeted-passed | d6ff2cf | 2026-10-17 |
| 埋点全覆盖的模拟器走查（iPhone 18 Pro / iOS 27.0，书籍来源，`-FIRDebugEnabled`）：GA4 属性注册 24 个事件级自定义维度（`screen_name`、`screen_class`、`app_version`、`build_number` 走内置维度）；设备日志逐条核对参数、DebugView 确认送达 26 种事件——开屏、五个标签页与 19 个子页曝光、分类切换、来源内搜索、打开作品（库 / 搜索 / 历史）、收藏增删、阅读器打开 / 关闭汇总、积分阈值、ATT 拒绝、激励广告结局与 busy、到账轮询、购买入口与商品加载、缓存清除与上限、崩溃诊断与使用统计开关、复制诊断码与账号 ID、历史筛选与选择模式、选类型、引导关闭、预检发起与结局、回前台。走查中修两处：`screen_view` 补 `screen_class`（缺省时 SDK 取 SwiftUI 宿主类名超过 100 字符被判无效、页面名一并丢失）；书 / 漫画详情的阅读器入口与跳转目标合成一个路由值（分开的 @State 在同一次更新里读到旧值，`reader_opened` 报成 `chapter_list`） | `BCA-OBS-001` | required | approved | implemented | simulator-passed | b54297b | 2026-10-17 |
| 埋点全覆盖在模拟器未走到的部分：视频与漫画链路（播放开始 / 失败 / 播完 / 关闭、换章方向、切线路）、站点登录与退出、来源添加 / 删除 / 撤销 / 启用、目录条目删除与规则更新、生成提交、购买结局与恢复、Apple 登录与退出、删除账号、云同步与首次恢复（模拟器 iCloud 不可用）、内容锁解锁、点开推送、启动失败 | `BCA-OBS-001` | required | approved | implemented | not-run | b54297b | 2026-10-17 |
| 关掉 sheet / 全屏页 / 盖层回到下层页面时补报曝光（走查观察：关掉引导屏后 `generation_preflight_started` 的 `firebase_screen` 仍是 `entry_guide`）：`.analyticsScreen(_:)` 改为维护可见页栈，onAppear 入栈并上报、onDisappear 出栈，出栈的是栈顶时等一轮主线程、新栈顶没报过就补报，全仓 19 处 `.sheet` / `.fullScreenCover` 与设置页购买盖层的宿主不用逐个写 `onDismiss`；书阅读器改用 `.analyticsScreen(resolving:)`（确定是文字书还是有声书前占住栈顶不上报），`AnalyticsScreenReporter` 不再对外暴露上报方法；合同第 1 节 `BCA-OBS-004`、第 2 节与 `screen_view` 注释写明补报 | `BCA-OBS-004` | required | approved | implemented | simulator-passed | 59780e4 | 2026-10-17 |
| 激励广告到账轮询加长到约 60 秒（用户 2026-10-17 裁定；走查观察：测试广告看完后 `ad_reward_credited` 报 timeout、余额随后才到账）：`CoinWalletStore.adRewardPollDelays` 由 2 / 4 / 6 秒改为 2 / 3 / 5 / 10 / 10 / 15 / 15 秒，版本号前进即停；`ad_reward_credited` 的 timeout 在代码注释与合同里写成「窗口内没到账」，迟到的到账不补报；PortalCore 另开 PR 在 SSV 回调里记录延迟，量出分布后再定窗口 | `BCA-OBS-001` | required | approved | implemented | targeted-passed | b669a06 | 2026-10-17 |
| Crashlytics 上报范围入合同并按合同补齐（用户 2026-10-18 裁定先写合同）：合同新增第 6 节与 `BCA-OBS-006` ~ `009`；规则执行失败改由 `RuleFailureDiagnostics.report` 同时报 I 组事件与非致命错误，原来只记 6 个失败点，现 14 个全记（补库页刷新 / 翻页 / 搜索 / 收藏状态、选中来源刷新、书详情、书阅读器，新增搜索翻页失败点）；启动装配失败另记一条；非致命错误只带原错误的 domain:code 与脱敏摘要（原错误 userInfo 会被原样上传，网络错误里带完整网址）；单条错误的键随错误上报、撤掉粘在后续报告上的四个全局键；崩溃诊断关闭时删除本机未发报告；页面曝光写 `screen=` 日志作页面轨迹；书详情、书阅读器、来源内搜索补写来源与规则阶段；文档闸门 A13 加调用边界 | `BCA-OBS-006` `BCA-OBS-007` `BCA-OBS-008` `BCA-OBS-009` | required | approved | implemented | not-run | bdd4dff | 2026-10-18 |
| 规则失败上报挡掉取消（Crashlytics 控制台核对发现：影视详情加载被取消时记成 Swift.CancellationError 非致命错误，过去 30 天 23 次、2 位用户，是最大的非致命问题；同一事件还带着与它无关的旧全局键 ruleStage=videoPlayback、errorCode=video-detail-error，这一点已由 `BCA-OBS-009` 的改动解决）：`RuleFailureDiagnostics.report` 统一挡掉 `CancellationError`、URL 取消与已取消任务里抛出的错误，只记一条 info 日志；合同第 6.1 节「刻意不记」写明做法 | `BCA-OBS-007` | required | approved | implemented | static-audit-passed | dd7fd17 | 2026-10-18 |

## 10. 统一日志

设计与裁定见 Claude 文档「BrowseCraft 统一日志方案设计」（https://claude.ai/artifact/PGu1HEr4yyLCqozdfuqFi1），合同见 [design/Logging-Design.md](design/Logging-Design.md)。

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 第 1 批·合同（用户 2026-10-18 裁定设计书第 7 节七项全按推荐）：新增 Logging-Design.md 与 `BCA-OBS-010` ~ `017`；`BCA-ARCH-005` 改为只经 `AppLog`；埋点合同第 6.2 节日志行一句改为指向 `BCA-OBS-017`；architecture.md 模块表加 BrowseCraftLog | `BCA-OBS-010` `BCA-OBS-011` `BCA-OBS-012` `BCA-OBS-013` `BCA-OBS-014` `BCA-OBS-015` `BCA-OBS-016` `BCA-OBS-017` `BCA-ARCH-005` | required | approved | implemented | static-audit-passed | 6d6b6e6 | 2026-10-18 |
| 第 2 批·建包与换管道：新仓库 BrowseCraftLog（`AppLog`、`LogLevel`、`LogCategory`、`LogValue`、`LogRecord`、出口协议与 `InMemoryLogSink`，`ErrorDiagnostics` 随之搬入）；Core / Domain / Runtime / APIKit 与 `project.yml` 加依赖；App 的 `OSLogSink` 为全仓唯一 `Logger(`，`BrowseCraftApp.init` 第一件事装出口；Domain 删 `RuleRuntimeDebugLog`，`RuleExecutionLogger` 改为 `AppLog` 薄包装 | `BCA-OBS-010` `BCA-OBS-011` | required | approved | implemented | full-suite-passed | 6d6b6e6 | 2026-10-18 |
| 第 3 批·收拢旧出口：旧 `AppLog` 43 处、`AppDebugLog` 99 处、`IAPDiagnostics` 与 `PortalSessionDiagnostics` 83 处、`AccountDeletionDiagnostics` 12 处、`CloudSyncDiagnostics` 15 个方法全部改成事件 + 类型化字段；`IAPDiagnostics` 只留错误码映射，`PortalSessionDiagnostics` 与 `AccountDeletionDiagnostics` 删除，`CloudSyncDiagnostics` 保留为 `AppLog` 的薄包装；`AppDebugLog` 的自由文本改为 debug 级结构化事件，字段先用 `text` 过渡 | `BCA-OBS-010` `BCA-OBS-011` `BCA-OBS-012` | required | approved | implemented | full-suite-passed | 6d6b6e6 | 2026-10-18 |
| 第 4 批·公共钩子：启动各步耗时、scenePhase 与内存警告、页面曝光（经 `AnalyticsScreenReporter`）、`AlamofireHTTPClient` / 网页渲染 / 两个预检取页 / 有声书音频、`PortalAPIClient.sendData`（路径模板）、`ImagePipelineFailureLogger`、`RuntimeStageLog.measure` 包住三个运行时 12 个公开入口与 `RuleFailureDiagnostics.report`、`AppDatabase` 打开与迁移 | `BCA-OBS-014` | required | approved | implemented | full-suite-passed | 6d6b6e6 | 2026-10-18 |
| 第 5 批·补空白与吞错：扫出 92 个不再抛出的 `catch`，真正吞掉的约 40 处补 `error`（收藏、历史、云同步页、内购会话、coin、阅读器书签、站点登录等），预期内不记的写明理由；Core 校验失败记 notice、条目被拒记 debug；`try?` 现存 230 处按文件登记进 `scripts/try-optional-baseline.txt`，只许收敛 | `BCA-OBS-015` | required | approved | implemented | full-suite-passed | 6d6b6e6 | 2026-10-18 |
| 第 6 批·本机文件、导出与 Crashlytics 日志行：`LogFileSink`（Caches/Logs 两个 5 MB 文件轮换、info 及以上、每行 JSON）、`CrashlyticsLogSink`（notice 及以上只写类别与事件名，经 `CrashDiagnostics.logLine`，采集关闭不写）、设置页「隐私与诊断」加「导出诊断日志」行（系统分享面板，三语文案，暂用诊断码图标，`support_info_copied` 加 `diagnostic_log`）、删除账号本机清理时删日志文件 | `BCA-OBS-016` `BCA-OBS-017` | required | approved | implemented | full-suite-passed | 6d6b6e6 | 2026-10-18 |
| 统一日志闸门：`check-architecture-boundaries.sh` 覆盖 BrowseCraftLog 包，禁 `debugPrint` / `NSLog` / `os_log` / `AppDebugLog` / `RuleRuntimeDebugLog`，`Logger(` 与 `import OSLog` 只许在 `OSLogSink.swift`，`try?` 按基线只许收敛；文档闸门 A10 读五个兄弟包，A13 加 `LogCategory` 与合同第 5 节双向核对 | `BCA-OBS-010` `BCA-OBS-011` `BCA-OBS-015` | required | approved | implemented | static-audit-passed | 6d6b6e6 | 2026-10-18 |

## 11. 活动与生成率提示

设计与裁定见 Claude 文档「BrowseCraft 活动与生成率提示框设计书」（https://claude.ai/artifact/J3NzxhSg1grTQmCgzq442M），画布见「活动与生成率提示」（https://claude.ai/artifact/6krDDFMgGhVrgLhFXRkDXP），合同见 [design/Campaign-And-Rate-Notices-Design.md](design/Campaign-And-Rate-Notices-Design.md)。

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 合同（用户 2026-10-18 裁定十二项全取 A）：活动弹窗与新注册欢迎页只经 In-App Messaging、网址输入页「取页方式」卡片里按地区的生成成功率一行、设置页「通知」分组的「活动推送」开关（只管活动推送）、锁屏活动推送走现有 APNs、不接 FirebaseMessaging、coin 只在服务端入账、服务端依赖与一次活动的固定顺序 | `BCA-UI-004` `BCA-UI-005` `BCA-SYNC-012` | required | approved | implemented | static-audit-passed | 00f6f70 | 2026-10-18 |
| App 侧实施：`project.yml` 链接 `FirebaseInAppMessaging-Beta`（默认显示组件）、网址输入页「取页方式」卡里的成功率一行与 APIKit `GET /v1/generation-rates` 客户端、设置页「通知」分组与图标 `SettingsCampaignPush`、`PushDeviceRegistrationCoordinator` 与 `POST /v1/push/devices` 带 `marketingOptIn` 与 `language`（App 界面语言 en / zh-Hans / zh-Hant）、登录返回解 `accountCreated` / `signupGrantCoins` 并在新注册拿到赠送时触发 `welcome_new_account`、活动推送点击刷新余额、埋点登记（`push_opened` 的 `campaign`、`setting_changed` 的 `campaign_push`、In-App Messaging 三个自动事件）、三语文案 | `BCA-UI-004` `BCA-UI-005` `BCA-SYNC-012` | required | approved | implemented | not-run | 78d2233 | 2026-10-18 |
| App 侧实施的离线测试：随 2026-10-20 整个 `BrowseCraftTests` 测试目标跑过（问题报告那一轮，Swift Testing 657 个全过），本项没有单独的用例 | `BCA-UI-004` `BCA-UI-005` `BCA-SYNC-012` | required | approved | implemented | full-suite-passed | 5142438 | 2026-10-20 |
| 真机验收（2026-10-19，iPhone 15、繁中系统、Debug 1.0 (20)）：设置页「通知」分组——未登录变灰、默认关、打开后服务端 `marketing_opt_in` 1 / `language` zh-Hant / `client_country` JP、系统通知被关时警示句与「前往設定」跳转、恢复后回到正常说明、退出时设备注销（DELETE 204）、重新登录开关恢复并重新登记、深色；新注册欢迎页——从没用过的 Apple ID 登录后弹卡片模板欢迎页（繁体系统显示简体，合同第五节预期），服务端同刻 `signup_grant` 3000，点「开始使用」后余额 3000，同账号重登不弹、不新建账号。未验：成功率一行有数据时的文案（等新账号的生成进次日汇总）、活动推送点击（活动脚本未做） | `BCA-UI-004` `BCA-UI-005` `BCA-SYNC-012` | required | approved | implemented | device-passed | de8fcae | 2026-10-19 |
| 隐私说明（PortalCore 部分在 PortalCore 仓，检查点为 PortalCore 提交，2026-10-19 随 PortalCore `a20f22e` 部署）：隐私权政策页繁中与英文补「活動推播」开关与界面语言、按 IP 推估国家只存两位国家码不存 IP（网址输入页只查不存）、In-App Messaging 会传 Firebase 安装识别码、署名 IP Geolocation by DB-IP（CC BY 4.0），生效日期 2026-10-19；App Store Connect 隐私标签 2026-10-19 核对：已声明的「粗略位置」（与身份关联，含分析、App 功能、开发者营销）与「设备 ID」覆盖这次新增的国家码与 Firebase 安装识别码，不用改；标签里「设备 ID 用于追踪」与 App 一致（第一次播激励广告前请求 ATT），过时的是政策页 AdMob 一条，已随 PortalCore `9ea8f40` 改正并部署 | `BCA-UI-004` | required | approved | implemented | not-run | 4c857c6 | 2026-10-19 |
| PortalCore 侧实施之一（在 PortalCore 仓，检查点为 PortalCore 提交）：`POST /v1/push/devices` 接受 `marketingOptIn` 与 `language`，迁移 v0021 给 `push_devices` 加两列；不带时同一用户保留原值、token 换了用户清零；2026-10-18 已部署，新版 App 的设备登记不再被 400 | `BCA-UI-005` | required | approved | implemented | full-suite-passed | 13db2a4 | 2026-10-18 |
| PortalCore 侧实施之二（在 PortalCore 仓，检查点为 PortalCore 提交，2026-10-18 已部署）：`GET /v1/generation-rates`（D 方案：每档给 `rate` / `samples` / `successes` / `scope`）、DB-IP Lite 国家库与 `scripts/update_geoip.sh`、迁移 v0022（生成任务与设备的 `client_country`、汇总表 `generation_rate_summary`）、`scripts/generation_rates.py` 每日汇总；宿主机 crontab 已加每日汇总（03:30 UTC）与每月换库（每月 3 日），国家库 2026-10 版已就位，线上实测本机 IP 判为 JP | `BCA-UI-004` | required | approved | implemented | full-suite-passed | 8948944 | 2026-10-18 |
| PortalCore 侧实施之三（在 PortalCore 仓，检查点为 PortalCore 提交，2026-10-19 已部署）：`POST /v1/auth/apple` 返回 `accountCreated` 与 `signupGrantCoins`（建号事务里实际入账的新户赠送，12 个月内删号重注册为 0），`/v1/auth/refresh` 不带 | `BCA-SYNC-012` | required | approved | implemented | full-suite-passed | a20f22e | 2026-10-19 |
| PortalCore 侧实施其余（在 PortalCore 仓）：活动脚本（幂等入账 `campaign_grant` 与活动推送） | `BCA-SYNC-012` | required | approved | not-started | not-run | 83b489e | 2026-10-18 |

## 12. 页内问题报告

设计与裁定见 Claude 文档「BrowseCraft 页内问题报告入口设计书」（https://claude.ai/artifact/R1jd8HR8q6hKoSKh1vTjMB，含入口、面板与数据流三张图），合同见 [design/Problem-Report-Design.md](design/Problem-Report-Design.md)。

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 合同（用户 2026-10-19 裁定设计书 8.3 节十一项；第 11 项收窄入口）：只在库页与三种详情页放失败态小字链接与「…」菜单两个入口，详情页面板加「问题出在哪」（详情与目录 / 某一集的内容）与选集，阅读与播放的问题从详情页报；30 个问题码分 8 组；报告字段与清洗边界（不带搜索词）、失败快照单一入口、规则版本取目录下发的 `catalogSHA256`、PortalCore 报告接口与规则版本表、排查五步、埋点在实施时同提交登记 | `BCA-OBS-018` `BCA-OBS-019` `BCA-OBS-020` `BCA-OBS-021` `BCA-OBS-022` `BCA-UI-006` | required | approved | implemented | static-audit-passed | 7b0429b | 2026-10-19 |
| 隐私标签、隐私清单与政策页（政策页在 PortalCore 仓）：App Store Connect 隐私标签声明客户支持、浏览历史记录（App 功能、关联、不追踪），其他诊断数据改为关联，共 12 类（「搜索历史记录」同日撤回）；`PrivacyInfo.xcprivacy` 同口径；隐私权政策页繁中与英文「問題回報」一节，不含搜尋詞 | `BCA-OBS-019` | required | approved | implemented | static-audit-passed | 7b0429b | 2026-10-19 |
| 可选：书阅读器单章失败接住并上报（合同第八节，新失败点 `book_reader_chapter`、其余失败渲染说明页、`onError` 记日志）；入口收窄后不再是前提 | `BCA-OBS-020` | optional | approved | not-started | not-run | 86539af | 2026-10-19 |
| PortalCore 侧第一期（在 PortalCore 仓，检查点为 PortalCore 提交，2026-10-20 已部署）：迁移 v0023 `catalog_source_revisions`（写入挂在唯一写 `rule_json` 的仓储方法、回填现有来源）、目录与生成结果的来源明文带 `catalogSHA256`、迁移 v0024 与 `POST /v1/problem-reports`（可选 Bearer、`clientReportId` 去重、查表计数限流与 IP 窗口、256 KB、服务端清洗、按指纹再按时间对版本、站点侧标记、收报告时顺带清理过期报告与多余版本） | `BCA-OBS-019` `BCA-OBS-022` | required | approved | implemented | full-suite-passed | f079121 | 2026-10-19 |
| App 侧第一期（APIKit 部分在 APIKit 仓 `b5a2fa5`，已推送；2026-10-20 build 通过）：v11 `catalogRevision` 迁移与添加 / 跟随更新时写入、APIKit 发送与目录指纹解码、`RuleExecutionError` 的脱敏摘要、失败快照存储、日志片段、发送用例与适配器、报告面板（含「问题出在哪」与选集）、库页与三种详情页的两个入口、埋点登记（`problem_report_submitted`、`report_scope`、`problem_type`、`problem_report`）、三语 82 条文案。2026-10-20 模拟器走查：库页「…」报 list、影视详情「…」报 content（含选集）、库页失败态「报告问题」（临时注入 HTTP 503，失败快照与站点侧标记齐、规则版本 exact）、发送失败后「再试一次」四条经线上落库核对通过；漫画与站点书详情未走查。同日跑测试目标：Swift Testing 657 个全过（含 7 个新测试；修了 v11 漏登记迁移标识），XCTest 86 个里 1 个与本功能无关的 WebView 计时测试超阈值 | `BCA-OBS-018` `BCA-OBS-019` `BCA-OBS-020` `BCA-OBS-021` `BCA-OBS-022` `BCA-UI-006` | required | approved | implemented | simulator-passed | 5142438 | 2026-10-20 |
| 第一期之后：排查第 4、5 步的查询脚本（PortalCore 仓） | `BCA-OBS-022` | required | approved | not-started | not-run | 86539af | 2026-10-19 |
| 合同第七节两项用例补齐：`LogFileSinkRecentLinesTests`（会话 / 时间窗 / 类别过滤、条数与字节上限、旧文件在前与坏行跳过，3 条）与 `BookSiteDetailViewModelTests` 的选集默认值用例（有续读位置默认那一章并标来自历史、没有时第一章）；本机 Xcode 26.0.1（Swift 6.2.0）要对 `perform` 调用、方法引用、字面量算式做等价改写才能编——改写只留本机工作区、不入库（构建机的 Xcode 27 不需要）；改写后 iPhone 17 Pro / iOS 26.0.1 模拟器上两组 10 条全过 | `BCA-OBS-020` | required | approved | implemented | targeted-passed | e9ccd6be | 2026-10-20 |
| 其余页面的入口（来源内搜索、两种阅读器、有声书、视频播放器、来源页、规则目录）：用户 2026-10-19 取消，阅读与播放的问题改从详情页报 | `BCA-UI-006` | rejected | superseded | not-started | not-run | 86539af | 2026-10-19 |

## 13. 全量代码审计（2026-10-20）

审计报告、七项裁决（用户 2026-10-20 全部接受建议）与发布后路线图七批见 Claude 文档「BrowseCraft 全量代码审计报告 2026-10-20」
（https://claude.ai/artifact/RqbnQE2ZiEEtsQ3aLKbfPq）。本节只登记发布前清单十二项；发布后路线图待发布后另立项。
检查点为实施提交 e564973b（兄弟包同日提交：Core 514336a、Runtime 902b309、Domain af4d655、APIKit c83e40f）。

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 清单 #1 目录解密密钥闸门：`scripts/check-ad-configuration.sh` 在 PROD 归档时断言 `BROWSECRAFT_CATALOG_ENCRYPTION_KEYS` 非空且含 `prod-`；`BCA-BUILD-003` 补一句，HANDOFF 环境速查写「归档机必须有 release.local.xcconfig」。脚本两个分支本机空跑过（空密钥 exit 1、prod 密钥 exit 0），未归档 | `BCA-BUILD-003` | required | approved | implemented | targeted-passed | e564973b | 2026-10-20 |
| 清单 #2 `SourceDebugView` 整页 `#if DEBUG`（用户裁定）：来源行长按「详情」菜单项、`navigationDestination` 与状态一并包进；本地化基线的 19 条调试页键保留——闸门按构建配置读编译产物，Debug 构建仍会提取到 | `BCA-UI-003` | required | approved | implemented | not-run | e564973b | 2026-10-20 |
| 清单 #3 四个未提交文件：维持「只留本机」（用户裁定；裁决时已不在工作树），HANDOFF 把「归档必须用 Xcode ≥ 27」写成硬约束，本机已装 Xcode 27.0（27A266a） | 未编号 | required | approved | implemented | not-run | e564973b | 2026-10-20 |
| 清单 #4 中文界面会出英文的裸字面量：播放器「不可播放」10 条、阅读器登录墙 2 条（复用 `comic_detail_access_*`）、阅读器空页与页码、播放器受限页按钮（三目两分支都查表）、登录页保存失败弹框、临时资源详情页 8 条、引导失败页 2 键，共 27 键三语补齐；`💡 %@` 改 `Text(verbatim:)`；基线从 48 键收到 20 键（19 条调试页键 + 本地书架 `EPUB`），审计点名的 Update %@ / Add %@ / Continue Listening 等 13 键源码里已不存在，只删基线行 | 未编号 | required | approved | implemented | not-run | e564973b | 2026-10-20 |
| 清单 #5 错误分类器：`RuleExecutionErrorClassifier` 认 Core 的 `SourceRuntimeError`（`emptyContent` → `selectorEmpty`，其余 → `ruleConfiguration`）；站点书阅读器打开失败改显示 `userMessage(for:)`，书签增删失败只记日志不再换成失败页。Runtime 内统一只抛 `RuleExecutionError` 归发布后 | 未编号 | required | approved | implemented | not-run | e564973b | 2026-10-20 |
| 清单 #6 网址输入页本地拒绝：`local-rejection` 单独词条 `video_preflight_submit_failed_local`（不嵌原码、不说稍后重试） | 未编号 | required | approved | implemented | not-run | e564973b | 2026-10-20 |
| 清单 #7 确认的死代码删除：`LoadSourcesUseCase`、`primaryActionTitle` 链（含 `VideoContentGridView` 的 "Episodes"）、`LibraryViewModel.sourceName(for:)`、`SourcesViewModel` 的 `nilIfEmpty` / `replaceSource` / `recommendSourceImport` 及工厂与测试替身的注入、`loadLatestComicHistory` 与 `LoadLatestComicChapterHistoryUseCase`、`isRuleGenerationOutcome` 及其测试文件、`recordBlockedCapability`、资产 `SettingsPremium` 与预算行；工程已重新生成 | 未编号 | required | approved | implemented | static-audit-passed | e564973b | 2026-10-20 |
| 清单 #8 一行级性能（审计 C-1 / C-2 / C-4 / C-5 / C-6 / C-7 的发布前部分）：影视详情「继续看」改按来源查询；收藏 id 集合只选 `itemID` 列；云同步页 `currentUserSummary` 改 `fetchCount`；阅读器图片请求与漫画详情封面 / 章节顺序按 source 在 init 算一次（UA 选择仍每次套）；目录分组改存储属性随 `catalogSources` / outcomes 重建；Book 解析器五个正则走 `RegularExpressionCache`；APIKit 日期 formatter 只建一次（C-14） | 未编号 | required | approved | implemented | not-run | e564973b | 2026-10-20 |
| 清单 #9 吞错补 error 级记录（`BCA-OBS-015`）：Book 翻页、漫画详情 / 阅读页翻页、检测词表资源四处加 `AppLog.error(.rule, …)`；coin 余额落库改 do/catch 记 `.database`；`SourceConfiguration` 键存在而解码失败时把首个 `DecodingError` 带进 `debugDescription`（显式 null 仍当不存在）；APIKit `transportFailed(code:)` 带 `safeErrorCode`，请求失败日志多一个 `transportCode` 字段 | `BCA-OBS-015` | required | approved | implemented | not-run | e564973b | 2026-10-20 |
| 清单 #10 小缺口：换账号时 `clearSearch()`；书详情已加载后重取失败出横幅（`DetailChapterHeader` 的 extras 槽，与漫画同做法）；视频历史按标题删行限定 `workKey LIKE 'title::%'`（用户裁定，2026-07-06 引入时是开发库清理）；演示模式开关收成 Shared 的 `DemoModeFlag`（Release 恒 false），`AdPlaybackHandler` 与 `AppContainer` 两处改用它、不再各包 `#if DEBUG`；`@Sendable` / `Sendable` 四处补声明 | 未编号 | required | approved | implemented | not-run | e564973b | 2026-10-20 |
| 清单 #11 注释与文档：三个详情 VM 的 `displayTitle` 说明归位、空 MARK 删除；`BookReaderViewModel` / `LibraryView` / `SourcesView` / `SourcesViewModel` / `RootView` / `DiagnosticEnums`（35 个页面）/ `CatalogSourceListView` 的过期或孤儿注释改掉；迁移示例改 `v12.…` 不再与 v2 撞号；两处提交哈希从注释里去掉；模板空话注释 12 处改成实际说明；architecture.md §9「28 files」改 22。`LibraryView` 本地书架路由里「Audiobook player is coming in a later batch.」是隐藏入口的词条，未动 | `BCA-DOC-010` | required | approved | implemented | static-audit-passed | e564973b | 2026-10-20 |
| 清单 #12 之一：`Info.plist` 加 `ITSAppUsesNonExemptEncryption = false`（CryptoKit 只用 OS 内置算法） | `BCA-BUILD-004` | required | approved | implemented | not-run | e564973b | 2026-10-20 |
| 清单 #12 其余（控制台侧，用户自己做）：ASC 取消「在 Apple 芯片 Mac 上提供」（用户裁定）；CloudKit Production schema Deploy；核 GMA 12.14.0 自带隐私清单的跟踪声明；8 个 `InAppPurchasePlan` 对 ASC 5 个内购；GCP 给 Firebase API key 加 iOS bundle 限制；TestFlight 包导出日志看 path 是否 `host#xxxxxxxx`；ATS 例外 `content.mkzcdn.com`——2026-10-20 本机 `curl -I https://content.mkzcdn.com/` 得 403（TLS 通、防盗链拒绝），规则里的图片地址是否已是 https 未核，例外暂留 | 未编号 | required | approved | not-started | not-run | e564973b | 2026-10-20 |
| 清单实施后的 build 与全量测试（用户 2026-10-20 触发）：Xcode 27.0 / iPhone 17 Pro（iOS 26.5）build 通过，App 目标 XCTest 86 个 + Swift Testing 670 个（116 个套件）全过；包侧 Domain 8、APIKit 53、Runtime 46、Core 全过。途中修了三处：APIKit 两个 ISO8601 formatter 不能做 static let（Swift 6 非 Sendable 全局状态），改成每个解码器建一次；Book 翻页 do/catch 里 `page` 绑定要提到 do 外；`AppUserIdentityBootstrapperTests` 的计数器随 `@Sendable` 闭包改成 `OSAllocatedUnfairLock` | 未编号 | required | approved | implemented | full-suite-passed | e564973b | 2026-10-20 |
| 发布后：依赖大版本升级（用户 2026-10-20 裁定上架后一次一个）——Firebase 13.0.1、GoogleMobileAds 13.11.0、GRDB 7.11.1、Nuke 13.2.0、KSPlayer 最新提交；每个单独立行、各自全量测试与真机 | 未编号 | required | approved | not-started | not-run | e596422a | 2026-10-20 |
| 清单实施后的模拟器冒烟（iPhone 18 Pro / iOS 27.0，Debug，真实账号）：库页书籍列表与「上次听到」瓷砖、站点书详情（128 章、分段芯片、无横幅）、规则目录「我的生成」按天分组与 42 角标、「发现」示例与内部测试分区——改成存储属性的目录分组与书详情横幅槽都正常。未走到：Release 配置长按来源（#2）、站点书打开失败（#5）、预检挡下的提交（#6）、书详情重取失败横幅（#10），四处都要制造失败才看得到 | 未编号 | required | approved | implemented | simulator-passed | e564973b | 2026-10-20 |
