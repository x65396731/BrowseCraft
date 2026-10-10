# 实施状态

本文是瞬时状态的唯一承载，形态与取值由 [文档索引](README.md) 第 5 节定义。
C 类设计文档不再承载 `implemented` / `pending` / `passed` 这类状态。

每格恰好一个值（`BCA-DOC-004`）。一个工作项同时存在多种验证事实时拆成多行（`BCA-DOC-005`）。
被覆盖的旧值追加到 [history/status-log.md](history/status-log.md)（`BCA-DOC-006`）。

条款列写 `未编号` 的行，是条款编号（D3）尚未执行的结果，不是「没有约束」。

## 0. 读这张表的纪律

**本表的行不会随条款落地自动退休。** 开工前的三步核对（都是零成本）：在 `BrowseCraft/` 与四个包里
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
| PDF 与 CBZ 不接（PDF 见 `BC-BOOK-012`，CBZ 漫画线保持自研阅读器） | `BC-BOOK-012` | rejected | approved | not-started | not-run | f443602 | 2026-09-13 |
| 站点有声播放器后续项：界面样式、倍速与偏好入口（SDK 有 `AudioPreferences`，界面没露）、`mediaAPI` 与带签名音频（无语料）——从读书接线合同第十六节搬出立行 | `BC-BOOK-012` | optional | draft | not-started | not-run | 1c7bc61 | 2026-10-10 |

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
| 库页视频库重设计：自绘眉行与大标题、搜索与账号两个圆形按钮、视频类型色胶囊分类芯片贴顶、「上次看到」瓷砖（新增按来源取最近视频历史的只读查询）、两列海报墙（集数徽章压封面、爱心用视频强调色）、分页脚代替悬浮胶囊、骨架改两列、横幅与切换来源遮罩换统一取值、空状态新插画 `EmptyStateLibraryVideo`（七项裁定全取 A） | 未编号 | required | approved | implemented | not-run | a5209bf | 2026-10-08 |
| 库页视频库重设计的模拟器走查（真实登录账号，樱花动漫）：眉行与大标题、只有搜索一个圆按钮、芯片选中琥珀、两列海报与爱心、无 `latestText` 故无徽章、滚动后芯片贴顶（状态栏与芯片之间露海报已修）、切分类、进详情与返回、开一集后回库页出现「上次看到」瓷砖（无时长故无进度条）、深色、长按菜单；分页脚、分类出错横幅、切换来源遮罩、账号按钮、点瓷砖进播放器（片源不可用）、搜索结果页、空状态插画实际显示未走到 | 未编号 | required | approved | implemented | simulator-passed | a5209bf | 2026-10-08 |
| 影视详情与选集页重设计：固定深色头图区（海报模糊压暗 + 小海报 + 标题 / 元数据行 / 状态徽章）、右上收藏、通栏「继续看」（按本作品历史写继续 / 下一集 / 再看一遍 / 从第 1 集开始 / 播放）、简介折叠与署名行、线路芯片（与库页分类芯片共用 `LibraryChipBar`）、集号网格（数字集名紧凑、非数字按内容宽、上次看的集描边）、解析时格内转圈不盖遮罩、解析失败横幅；Core `SourceDetailAttribute.key` 透传规则 `metadata[].id`，App 按 key 摆位（八项裁定全取 A） | 未编号 | required | approved | implemented | not-run | 5545183 | 2026-10-08 |
| 影视详情与选集页重设计的模拟器走查（真实登录账号，低端影视）：电影页有历史——深色头图区、小海报、列表标题、元数据行（规则只给 `html[lang]` 的 zh-CN）、「新片」徽章、来源行、继续看按钮、简介展开 / 收起、单集格子描边与小三角；剧集页无历史——「播放」、右上收藏点了变实心且库页爱心同步；深色模式按钮与芯片换浅琥珀底墨字；数字集号网格、线路芯片、正序 / 倒序、下一集 / 再看一遍、受限 / 付费角标、解析失败横幅、没有选集 / 取失败态未走到（模拟器只有一个每部作品一条播放页的来源） | 未编号 | required | approved | implemented | simulator-passed | 5545183 | 2026-10-08 |
| 历史页重设计的模拟器走查：继续卡片三种类型色、看到哪里与进度条、筛选与某类为 0、只有一条、按天分组、左滑与长按删除及撤销（漫画整部删除与整部写回）、在库中查看来源、已暂停 / 已删除 / 未知 / 临时资源、空状态与去库里逛逛、深色、收藏页回归 | 未编号 | required | approved | implemented | simulator-passed | 9ebb107 | 2026-10-03 |
| 漫画详情与章节页重设计：漫画类型色淡底头部（封面 + 标题 / 作者 / 徽章 / 更新行 / 来源行）、右上收藏、继续卡片（上次页面缩略图、「13 / 45 页」与进度条）或「从第 1 话开始读」按钮、章节目录按标题形状选三列网格或行列表、≥ 60 章分段芯片滚到段首、按作品读全部章节历史做已读与上次读到标记、历史表追加 `pageCount`、受限与失败提示换页内横幅；向 fwq 提四条生成覆盖需求（九项裁定全取 A） | 未编号 | required | approved | implemented | not-run | a303af5 | 2026-10-08 |
| 漫画详情与章节页重设计的模拟器走查（真实登录账号，めちゃコミック）：淡底头部与列表标题优先、更新行是类型标签、「从第 1 话开始读」、行列表「1-1」编号柱、第 9 话起小锁、开一章回来后继续卡片「6 / 58 页」与进度条、已读 1 与上次读到竖条、正序 / 倒序切换、贴顶分区头停在固定按钮下、受限横幅在分区头里出现且「登录」打开来源登录页、右上收藏实心、深色；三列网格、分段芯片、作者 / 徽章 / 标签 / 日期、没有章节与取失败态未走到（线上只有一条漫画来源，没有纯编号目录与 60 章以上的作品） | 未编号 | required | approved | implemented | simulator-passed | a303af5 | 2026-10-08 |
| 漫画详情分段芯片的滚动锚点按分区头高度换算（合同第十四节原记的已知出入：锚点 `.top` 让段首两行压在贴顶分区头下；照站点书详情 `segmentScrollAnchor` 同一做法；按 AGENTS 未 build，未在模拟器看过） | 未编号 | required | approved | implemented | not-run | 2f37a46 | 2026-10-10 |
| 库页漫画库重设计：三列封面墙（封面圆角 10、标题两行 + 最新话一行类型色）、读过的作品封面左下压「读到 4-2」进度角标、只在已收藏时压小爱心、长按菜单加「继续读」、「上次读到」瓷砖（按来源读全部漫画章节历史的只读查询，一次读供瓷砖与角标）、骨架按类型三列、空状态插画 `EmptyStateLibraryComic`；删漫画卡片的 `libraryTitleText` 与写死的蓝紫色（七项裁定全取 A） | 未编号 | required | approved | implemented | not-run | fa57f00 | 2026-10-09 |
| 库页漫画库重设计的模拟器走查（めちゃコミック）：「上次读到」瓷砖（4-2 真夜中の逢瀬 · 6 / 58 页、进度条、时刻）、三列封面墙与「读到 4-2」角标、已收藏小爱心、最新话类型色一行、长按卡片「打开 / 继续读 · 4-2 / 取消收藏」且「继续读」直接进阅读器、从阅读器回来瓷砖时刻刷新、长按瓷砖「继续读 / 打开作品」且「打开作品」进详情（收藏与继续卡片对得上）、深色、底栏为系统原样；骨架、空状态插画、分类芯片、「打开作品」的反解路径、视频库回归未走到（线上只有一条漫画来源、模拟器上没有视频来源） | 未编号 | required | approved | implemented | simulator-passed | fa57f00 | 2026-10-09 |
| 库页书籍库重设计：单列书脊行（封面 60×80 带书脊线、书名两行、「最新 · 原文」、「读到 · 章节名」、行尾已收藏爱心、分隔线）、整站有声按 reader 规则 `contentType` 判（眉行「有声书」、封面耳机、「听到 / 上次听到 / 继续听」措辞）、长按「继续读 / 继续听」直接进阅读器、「上次读到」瓷砖（按来源读全部读书历史 + 瓷砖那一本的 `totalProgression` 进度条）、骨架书脊行形态、空状态插画 `EmptyStateLibraryBook`；删旧卡片与 `libraryTitleText`（十项裁定全取 A） | 未编号 | required | approved | implemented | not-run | a045eab | 2026-10-09 |
| 库页书籍库重设计的模拟器走查（小說狂人 czbooks.net，从目录加）：眉行「书籍 · 主机名」绿色、20 个分类芯片、搜索 + 账号按钮、书脊行（占位封面与真封面都带书脊线、「最新 · 原文」、分隔线）、读一章回来后「上次读到」瓷砖（章节名原文、全书进度条、时刻）与行的「读到 · 第3章 佛祖舍利」、长按行「打开 / 继续读 · 章节名 / 收藏」且收藏后行尾实心爱心、长按瓷砖「继续读 / 打开作品」且「继续读」直接进阅读器、从阅读器回来瓷砖时刻刷新、切分类瓷砖照留、深色、漫画库回归、底栏为系统原样；骨架（切分类太快没抓到）、空状态插画、整站有声（线上没有有声来源）、失败态未走到 | 未编号 | required | approved | implemented | simulator-passed | a045eab | 2026-10-09 |
| 站点书详情页重设计：页面底色头部（封面 72×96 带书脊线、书名、作者有才出、来源 · 分类、章数 / 有声书章数）、右上收藏（注入收藏用例）、继续卡片（章名 · 全书 % · 时刻 + 进度条，有声书写 `t=` 时间点）或「从第 1 章开始读 / 听」、简介透传后有才出、贴顶分区头 + 正序倒序 + ≥ 60 章分段芯片、编号柱行列表（解不出整行标题）、上次读到竖条与行尾章内进度、之前的行变淡、续读章先按读书历史 `chapterURL` 对、页内横幅 + 重试 / 登录、骨架与没有章节；`ComicChapterTitleParser` 认中文数字；装配器透传 `description`（十三项裁定全取 A） | 未编号 | required | approved | implemented | not-run | 6ba8846 | 2026-10-09 |
| 站点书详情页重设计的模拟器走查（小說狂人 czbooks.net）：页面底色头部（占位封面带书脊线、书名、来源 · 分类、「1,297 章」）、固定返回与收藏（点了实心、回库页对得上）、有历史的书继续卡片「第3章 佛祖舍利 · 全书 刚开始 · 时刻」、贴顶分区头 + 正序 / 倒序（芯片跟着反过来）+ 分段芯片（点了段首落在分区头下）、编号柱行列表与上次读到竖条 + 「读到 N%」、之前的行变淡、没读过的书「开始读 · 章名」、点行带章节进阅读器、回来后续读章 / 章内进度 / 继续卡片「全书 10%」刷新、继续卡片不带章节回到上次翻到的位置、深色；有声书、失败与登录横幅、没有章节、简介未走到（线上没有有声来源、规则不给简介） | 未编号 | required | approved | implemented | simulator-passed | 6ba8846 | 2026-10-09 |
| 来源内搜索页重设计：隐藏系统导航栏，自绘眉行（类型图标 + 「类型 · 来源名」）+ 「搜索」+ 40pt 圆形关闭；高 48 卡片底搜索框（聚焦 1.5pt 类型色描边、清空叉、键盘搜索键提交、提交收键盘）；结果眉行「“关键词” · N 个结果」（提交时定格的关键词）；结果区 `LibraryContentView` 按 kind 原样复用；未搜索 / 无结果用插画 `EmptyStateSearch` 顶对齐、搜索中按 kind 骨架、失败警示横幅 + 重试（登录墙且来源有登录页多「登录」，登录后自动重搜）；`performSearch` 可取消；接 `searchNextPage` / `loadNextSearchPage`；关闭再打开保留状态、换来源 `clearSearch()`（十四项裁定全取 A） | 未编号 | required | approved | implemented | not-run | 25f754b | 2026-10-09 |
| 来源内搜索页重设计的模拟器走查（小說狂人 czbooks.net，iPhone 18 Pro / iOS 27.0）：眉行「书籍 · 小說狂人 · 玄幻奇幻」青绿图标、「搜索」+ 圆形关闭、进页聚焦且搜索框青绿描边、占位「搜索 来源名」、插画 + 两行说明顶对齐、有字出清空叉、回车提交后描边消失、结果眉行「“100” · 40 个结果」、书脊行结果、点行推入站点书详情（导航栏仍隐藏）再返回结果保留、滚到底没有分页脚、关闭再打开结果保留且不弹键盘、清空回未搜索态并重新聚焦、深色（结果与未搜索）；搜索中骨架（请求太快没抓到）、无结果（czbooks 对任意关键词都回 40 条）、失败 / 登录横幅、分页脚、视频与漫画来源的结果版式未走到；模拟器软件键盘被硬件键盘顶掉、工具不能输入中文，关键词用的是数字与字母 | 未编号 | required | approved | implemented | simulator-passed | 25f754b | 2026-10-09 |
| 规则目录页打开时「我的生成」有条目就优先落在「我的生成」（打开时按已有数据定段、首次拉取完成后再定一次、用户点过分段就不再改） | 未编号 | required | approved | implemented | not-run | 26d1b3e | 2026-10-09 |
| 我的生成「删一条失败记录又冒一条」：App 侧删失败记录时把同一入口的全部失败一起软删除（`SourcesViewModel.hideOutcomes`）；PortalCore `OUTCOME_LIMIT` 20 → 200 并补测试（服务端那半在 PortalCore 仓） | 未编号 | required | approved | implemented | not-run | 26d1b3e | 2026-10-09 |

## 3. 影视线运行期

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 运行期广告过滤承接规则匹配结果（App 侧对规则匹配到的候选执行过滤） | `APP-MEMO-008` | required | approved | implemented | full-suite-passed | ff58d6a | 2026-08-29 |
| jable.tv M3U8 播放规则的抽取根因（结论已由 fwq `BC-PLAYBACK-049` 承接） | `BC-PLAYBACK-049` | required | superseded | not-started | not-run | 4a3814b | 2026-08-21 |
| 直接请求收到挑战页时回退 WebView 再取一次（toonily 重生成后规则不带 `needsWebView`，真机三部作品打不开：手机出口直接请求章节页 403 Cloudflare 挑战、服务器出口 200；`DefaultPageLoader.loadContent` 捕获 `antiBot` 后走 `renderedPageContentLoader`，其它错误不回退；fwq `APP-MEMO-026`） | `BCA-RUNTIME-005` | required | approved | implemented | targeted-passed | 9f328d0 | 2026-10-06 |
| WebView 过挑战后把站点 Cookie 回写系统存储 + 书类封面请求带上来源请求配置（`BCA-RUNTIME-005` 2026-10-07 补充两处；xbanxia 真机封面全失败：列表经 WebView 过 Cloudflare，封面请求 `hasCookie=false`、图床回挑战页；第一处上线后复验仍失败，查出书类封面请求配置为空、Cookie 策略缺省不带系统 Cookie；第三处：回写的 `cf_clearance` 按图床地址取不回，改为只用公开属性重建再写入；用户「修，现在实施」，真机确认封面显示） | `BCA-RUNTIME-005` | required | approved | implemented | device-passed | 11c4949 | 2026-10-07 |
| 列表分页页码按 `startPage + N − 1` 代入（0 起页码站 rouman5 / 3kor；fwq `BC-LIST-124` / `APP-MEMO-027`）：Core `PaginationRule.startPage` 与 `sitePageNumber(forPage:)`、影视 / 漫画 / 书三处代入点、目录请求 `features=startPage` 能力声明；Core 3 例 + Runtime 24 例过、App 构建过，未发版 | `BCA-RUNTIME-006` | required | approved | implemented | targeted-passed | 587a99c | 2026-10-06 |
| 站点按状态码拒绝不再报成「规则解析出错」（xjortho 拦桌面 UA 返回 403，正文被当成列表页解析；fwq `MEMO-App-请求被拒显示成规则解析出错`）：直接请求最终状态码 ≥ 400 时先认挑战页、其余抛 `RuleExecutionError.httpStatus`（Domain `d1d5dac`），分类器按状态码四类文案、诊断记 `network`；`loadData` 与 WebView 通道不在范围；用例已写（7 例），四道代码闸门过，未发版 | `BCA-RUNTIME-007` | required | approved | implemented | full-suite-passed | 07a0231 | 2026-10-10 |

## 4. 身份与同步

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 身份边界切换到 Sign in with Apple 与后端生成的 AppUser UUID | 未编号 | required | approved | implemented | full-suite-passed | eeb288e | 2026-07-28 |
| CloudKit 上传前的安全门禁——记录大小预算（900 KB / 800 KB / 8 KB）、URL userinfo、本地 account scope 泄漏：`CloudSyncPayloadSecurityValidator` 已实施并接线 | `BCA-SYNC-008` | required | approved | implemented | full-suite-passed | bed4ab3 | 2026-07-25 |
| CloudKit 门禁的 Header 名称拦截与 `context.*` / Request Body / `keyHex` / `ivHex` / constant value 字面量扫描——实现有意收窄为「不推测站点规则常量是否敏感」，13 例固定输入钉住该取值 | `BCA-SYNC-008` | optional | superseded | not-started | full-suite-passed | bed4ab3 | 2026-07-25 |
| Phase0 审计的安全结论已提升为 C：排除数据、冲突与删除、凭据引用三条成 `BCA-SYNC-009` ~ `011`，未实施的全面扫描部分显式声明为有意收窄 | `BCA-SYNC-009` `BCA-SYNC-010` `BCA-SYNC-011` | required | approved | implemented | static-audit-passed | 69779bb | 2026-09-19 |
| RSS 整体下线：删功能、迁移 v6 清存量、同步跳过 rss、书籍收藏改记 book | 未编号 | required | approved | implemented | full-suite-passed | f263274 | 2026-09-16 |
| 删除来源连带删除历史与收藏：用户删除时删三张历史表、给收藏写删除标记并入队；iCloud 应用远端删除时删本机历史并清空当前选择；删除后底部可撤销并原样写回；删除与撤销后刷新历史、收藏与库页；底部文案改写 | `BCA-DB-004` `BCA-DB-005` | required | approved | implemented | full-suite-passed | c2b2437 | 2026-10-03 |
| 删除来源连带删除的模拟器走查：左滑删除非内置来源与长按删除内置来源，历史、收藏、库页爱心随删除消失、随撤销回来，撤销后改回当前来源 | `BCA-DB-004` `BCA-DB-005` | required | approved | implemented | simulator-passed | c2b2437 | 2026-10-03 |
| 续看位置同步到 iCloud：每部作品一条续看记录（云端 `HistoryEntry` 21 个字段，已部署到 Production）、本机账本对比找改动、来源先于历史下载、删除与恢复、退到后台时同步、云同步页第三行改为作品数 | `BCA-SYNC-009` | required | approved | implemented | full-suite-passed | 7102bba | 2026-10-04 |
| 续看位置同步的模拟器走查（真实账号，Development 环境，单台设备）：迁移后正常启动、新增来源并产生一条视频历史、退到后台触发同步并上传、云同步页第三行显示作品数、来源已删除的历史不计入也不上传、删除历史后退到后台上传删除标记；两台设备互相接续与书的阅读位置未走到 | `BCA-SYNC-009` | required | approved | implemented | simulator-passed | 7102bba | 2026-10-04 |

## 5. 文档架构迁移

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D0 冻结基线：现状量化、逐份 C/S/H/E 判定、五处 RSS 漂移 | `BCA-DOC-001` | required | approved | implemented | static-audit-passed | 2ce6b99 | 2026-09-19 |
| D1 建索引 + 只移动文件：12 份迁入 `docs/`，新建索引，修五处 RSS 漂移 | `BCA-DOC-002` `BCA-DOC-003` | required | approved | implemented | static-audit-passed | 2ce6b99 | 2026-09-19 |
| D2 状态出设计文档：四份 C 类的状态头与两处验证节按三分法分流 | `BCA-DOC-007` `BCA-DOC-008` | required | approved | implemented | static-audit-passed | 812fde5 | 2026-09-19 |
| D3 条款编号与混装拆分：分配 `BCA-*` ID，fwq 已定义的改引用点，拆混装文档 | `BCA-DOC-001` `BCA-DOC-002` | required | approved | implemented | static-audit-passed | 812fde5 | 2026-09-19 |
| fwq 的 `protectedResource` 与 `executionPolicy` 两句只有正文没有稳定 ID——2026-10-03 裁定不请 fwq 分配：它们是生成器的发布偏好与默认值，不是 App 的执行约束，App 侧文档本就未引用 | `BCA-DOC-001` | rejected | superseded | not-started | not-run | a4433eb | 2026-10-03 |
| C 类里的散文硬条款一次扫完编号：逐行分类后确认真条款 22 条，其余是描述句、章节标题与已编号条款的续行 | `BCA-DOC-002` | required | approved | implemented | static-audit-passed | c0a72fe | 2026-09-19 |
| D4 机器闸门 `scripts/check-docs.py`：A1–A10 十项，每项经反向植入验证会红 | `BCA-DOC-010` | required | approved | implemented | targeted-passed | a330927 | 2026-09-19 |
| D5 `HANDOFF.md` 会话入口：四样内容，只记现查口径不记数字，只记纯 App 侧的工作 | `BCA-DOC-011` | required | approved | implemented | targeted-passed | a2adece | 2026-09-19 |
| fwq 可写文件里指向 App 文档的九处旧路径已更正；`docs/history/` 十一处按只读归档未动，查迁移对照表 | 未编号 | required | approved | implemented | static-audit-passed | 4fd6087 | 2026-09-19 |
| `BrowseCraftCore` 文档迁移：十份进 `docs/design` 与 `docs/history`，建索引，三份混装按节三分 | `BCA-DOC-009` | required | approved | implemented | static-audit-passed | 69233d1 | 2026-09-19 |
| Core 预检合同按 v3 收敛：一跳与 family coverage 归档，组件名对齐代码，白名单两条撤回 | `BC-PREFLIGHT-030` | required | approved | implemented | static-audit-passed | 6f6dc80 | 2026-09-19 |
| A10 文档点名的代码符号必须存在（fwq `BC-DOC-028` 那类）：白名单只许收敛，识别家族通配与路径段 | `BCA-DOC-014` | required | approved | implemented | targeted-passed | 15394c2 | 2026-09-19 |
| `scripts/update-rules-package.sh` 已确认是死脚本并删除：`BrowseCraftRulesKit` 仓库不存在、`project.yml` 零引用、`Package.resolved` 零命中 | 未编号 | required | approved | implemented | static-audit-passed | 2b4bd07 | 2026-09-19 |
| `BookBookmarksSheet` 是设计里不存在的类型名——书签功能已实现，呈现层内联在 `BookReaderView`；文档已按实际改写，白名单撤回 | `BCA-DOC-014` | required | approved | implemented | static-audit-passed | 2b4bd07 | 2026-09-19 |
| 规则编辑入口下线：`SourceDebugView` 的「Edit JSON」摘除、两个零引用编辑视图删除，规则一律只读 | `BCA-UI-003` | required | approved | implemented | static-audit-passed | 1b990b5 | 2026-09-19 |
| 规则编辑下线遗留的死代码链已清：五个文件 207 行，含 Service 的两个注入依赖与组合根、测试替身的装配 | 未编号 | required | approved | implemented | full-suite-passed | 4527def | 2026-09-19 |
| 规则编辑下线遗留死代码第二批：更新 / 复制 / 导入 / 导出四类用例、Coordinator 与两个测试文件整链删除 958 行，只读格式化独立为 `SourceRuleDebugJSONFormatter` | `BCA-UI-003` | required | approved | implemented | full-suite-passed | af2e331 | 2026-09-19 |
| `scripts/regenerate-project.sh` 已恢复：CLT 升到 27.0、arm64 xcodegen 2.46.0 从源码装好，`/usr/local/bin` 的 x86_64 旧链接已移除，bash 与 zsh 下都命中 arm64 版 | `BCA-BUILD-001` | required | approved | implemented | targeted-passed | af931e1 | 2026-09-19 |
| 模拟器 `build-for-testing` 链接失败已修：`BrowseCraftRuntime` 的 `Package.swift` 缺对 `BrowseCraftRuleModels` 的 product 声明，动态链接时符号解析不到；generic destination 静态链接下不暴露 | `BCA-ARCH-002` | required | approved | implemented | full-suite-passed | 4527def | 2026-09-19 |
| iOS 18.5 模拟器运行时跑不了测试（缺 `libswiftWebKit.dylib`）——裁决不修，测试口径统一到 iOS 26 及以上；`HANDOFF.md` 与设计文档的命令已改 iPhone 17 Pro | 未编号 | rejected | approved | not-started | targeted-passed | af931e1 | 2026-09-19 |
| 9 条 `BCA-*` 定义点曾只在被 `.gitignore` 的 `AGENTS.md` 里——已迁入跟踪的 C 类文档，`AGENTS.md` 收成纪律与指针（与 fwq 同构），闸门加 A11 守住 | `BCA-DOC-015` | required | approved | implemented | static-audit-passed | 30f9713 | 2026-09-19 |

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
