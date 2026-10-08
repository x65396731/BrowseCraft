# 漫画详情与章节页的视觉与信息结构重设计

设计稿（画布，含带名目录、纯编号目录、sfacg 实际效果、深色、めちゃコミック实际效果、正在取详情、没有章节、取失败、受限横幅、尺寸与取值，共 10 张）：
[漫画详情与章节页重设计](https://claude.ai/artifact/LGbxVijN2p57as4TSpQibM)；设计文档：[漫画详情与章节页重设计](https://claude.ai/artifact/WZwK8v1qxEvUDHEJS3efAB)；
向 fwq 提的生成覆盖需求：[fwq 需求：漫画详情与章节字段的生成覆盖](https://claude.ai/artifact/K7yhDMsdKsgQ7fWbM6sjzR)。
设计与实施状态见 [STATUS.md](../STATUS.md)。颜色、圆角、字号与交互约定沿用影视详情页、库页视频库与历史页
（[影视详情页](Video-Detail-Page-Redesign-Design.md)、[库页视频库](Library-Video-Page-Redesign-Design.md)、[历史页](History-Page-Redesign-Design.md)），本页不新增色值。

## 一、背景

`ComicDetailView` 是点漫画封面进入的页：模糊封面头图 + 「阅读」按钮卡 + 标签条 + 「简介」「信息」两张卡 + 一张「章节」卡里的一列扁平行。影视详情页改完之后这一页的问题最集中：

- 头图与影视详情改前是同一个做法：封面拉成 1.12 倍屏宽再模糊，标题压在上面；作者行没有作者时写来源名，把「没有」写成一句假话。
- 「阅读」按钮与「N Chapters」是词条里没有的硬编码英文。
- 章节是一列带 › 的行，每行序号圈 + 标题 + 副标题 + 「Paid」字样：MYCOMIC 一部作品 180 章、sfacg 近 1000 章，要滚上百屏。
- 看到哪一章、读到第几页只体现在按钮文案里；读过哪些章没有任何标记——漫画是逐章读的，「读过」比影视更要紧。
- 章节标题的形状站与站不同（「第94话」「VIP第993话」「第1249话 乌云乌云别找我麻烦。」「1話(1):あるまじき瞳の色」），同一种行把它们摆得一样宽松或一样拥挤。
- 受限章节与取失败都弹系统警告框；没有收藏入口。
- 「信息」卡逐行列出发布 / 更新 / 许可 / 编号 / 图数，三条漫画规则一个都没取到，卡片在真实来源上几乎总是空的。

## 二、规则实际给什么数据

页面只能画规则真给的东西。按 Core 运行期模型（`SourceDetailOutput` 的 `metadata` + `chapters`）和三条能拿到的漫画规则——线上目录唯一的漫画来源めちゃコミック、PortalCore `rules/` 里的 MYCOMIC 与 sfacg——逐字段核对，章节名的实际形状另看 fwq 语料与线上作品页。

**详情**（`SourceDetailMetadata`，规则 detail `fields`）：

| 字段 | 规则里的来源 | 三条规则的现状 | 页面怎么用 |
| --- | --- | --- | --- |
| 标题 | detail `title` | 三条都有；めちゃコミック与 manga18 取的是页面 `<title>`，带站名前后缀 | 大标题用列表项标题（用户点进来时看到的名字），列表没给才用 detail `title` |
| 封面 | detail `cover` | 三条都有（og:image 或正文图） | 头部封面；没有退到列表封面，再没有 `ComicDetailPlaceholder` |
| 简介 | detail `description` | 只有 MYCOMIC 有 | 简介块，没有不出 |
| 作者 / 状态 / 分类 / 标签 / 语言 | detail `author` `status` `category` `tags` `language` | 三条都没生成 | 作者行、状态与分类徽章、标签条——有才出，现有来源上全部不出 |
| 发布 / 更新时间、许可、编号、总图数、相册与二级页链接 | detail `publishedAt` `updatedAt` `license` `idCode` `totalImages` `photoAlbumURL` `secondLevelPageURL` | 三条都没生成 | 收进简介块下方的小字行；相册 / 二级页做成链接行；都没有就整块不出 |
| 额外属性 | `attributes`（`SourceDetailAttribute`，含影视那轮透传的 `key`） | 三条都没生成 | 简介块下方「label · value」小字 |
| 更新状态 | 列表项带进来的 `latestText` | 三条列表规则都取；めちゃコミック取到的是类型标签，sfacg 取到的是整条卡片文字 | 头部的更新行，照原文一行显示，没有不出 |

**章节**（`SourceDetailOutput.chapters`，每条 `SourceChapter`；HTML 走 detail `ChapterRule`，接口走 `DetailChapterAPIRule`）：

| 字段 | 规则里的来源 | 现状 | 页面怎么用 |
| --- | --- | --- | --- |
| 章节名 | `title` / `titlePath`（必有） | MYCOMIC「第94话」（纯编号）；sfacg「VIP第993话」（VIP 是站点夹在链接里的字样）；めちゃコミック「1話(1):あるまじき瞳の色」（话数 + 分节 + 话名）；语料里 patternrecognition「第1249话 乌云乌云别找我麻烦。」 | 目录主文字；能解出数字的用数字做编号柱，解不出的用显示顺序序号 |
| 阅读页地址 | `url` / `urlTemplate` `urlPath`（必有） | 都有 | 点章进阅读器；也是与章节历史对上的键（`chapterKey` 默认就是这条 URL） |
| 副标题 | `datetime` / `descriptionPath` → `subtitle` | 三条都没生成 | 行右侧的日期小字；没有不出 |
| 排序 | `sort`（+ 接口 `orderPath`） | MYCOMIC `none`、sfacg `ascending`、めちゃコミック未声明（页面顺序是正序） | Core 已排好；App 只决定正序 / 倒序的显示翻转与「第 1 话」是哪一头 |
| 受限 | `restriction` + `restrictedValues`（`BC-COMIC-147`）/ `restrictionPath` → `isRestricted` | めちゃコミック已生成（href 首段 `chapters` 即受限，`free_chapters` 可读）；MYCOMIC、sfacg 没有，sfacg 的 VIP 只在标题文字里 | `true` 才标小锁并走登录提示；`nil` 不标、不猜 |
| 付费 | 只有接口规则的 `paidPath` + `paidValues` → `isPaid`；HTML 规则没有这个字段 | 没有 | `true` 才标小币 |
| 分组 | `ChapterRule.section`（容器，可带 `title`） | MYCOMIC 与 sfacg 声明了容器，但 Core 的 HTML 路径只用它找条目，分组标题没进 `SourceChapter` | 不画分组；分段跳转由 App 按章数切 |
| 章节自身分页 | `chapterPagination`（`BC-COMIC-146`） | めちゃコミック有（3 页）；Runtime `ComicSourceDetailLoader` 聚合后再给 App | App 拿到的已是全量，不画「加载更多」 |

**历史**（本机 `comic_chapter_history`，一章一条，与影视的一部作品一条不同）：`ComicChapterHistory` 的 `chapterKey` `chapterURL` `chapterTitle` `visitedAt` `lastPageIndex` `lastPageImageURL` 等。按来源 + `comicItemID` 能拿到本作品读过的每一章；最近一条就是「上次读到」。`lastPageIndex` 是看到第几页，`lastPageImageURL` 是那一页的图（做继续卡片的缩略图）；**没有这一章一共几页**——阅读器解析时知道（`ReaderChapter` 的 `pageImageURLs`）但没存，所以「13 / 45 页」要追加字段（第九节）。

**线上目录的实际效果**：公共目录里漫画只有めちゃコミック一条，MYCOMIC 与 sfacg 都没发布；模拟器库里现在没有漫画来源、漫画历史 0 条。按它的规则和线上作品页逐块核对，会出现的是封面、标题（靠「列表标题优先」才干净）、来源行、更新行（内容是类型标签）、「从第 1 话开始读」、行列表（编号柱「1-1」+ 话名）、第 9 话起的小锁、正序 / 倒序、收藏；不会出现的是作者行、徽章、标签条、简介、日期、小币、分段芯片（约 30 章）。继续卡片与已读标记读过一章就有，不依赖规则。

## 三、入口、相邻页面与范围

- **入口**：库页漫画封面、搜索结果、收藏页行、历史页与库页「打开作品」都推入本页；进入后隐藏底栏，左上返回。
- **出口**：点一章或「继续阅读」推入漫画阅读器 `ReaderView`（阅读器自己有上一话 / 下一话）；阅读器返回回本页，本页重读历史，已读标记与继续卡片跟着换。受限章节走现有登录提示与 `SourceLoginView`。
- **相邻**：上一页是库页的漫画库（三列封面卡，外壳已随库页视频库那轮改成统一语言）。本页封面就是那张封面，分段芯片沿用库页分类芯片（`LibraryChipBar`），继续阅读与选中态用漫画类型色。
- **与影视详情的区分**：影视是固定深色头图 + 线路芯片 + 集号网格，因为集只有号、点了就播；漫画章节有名字、有日期、逐章读、动辄几百章，所以本页是浅色头部 + 继续卡片 + 可读标题的目录。两页共用同一套圆角、字号、芯片与按钮规格，只换版式和类型色。
- **范围**：本文定漫画详情页的全部——头部、继续阅读、简介与属性、章节目录（版式、排序、分段、已读）、收藏、各状态，外加为了把数据摆对位置要追加的字段（第九节）。
- **不在范围**：阅读器、章节解析与登录流程的判断（`prepareToOpen` / `completeRequestedSourceLogin` 不动）、历史的写入、规则本身、库页漫画库的网格（另立项）。

## 四、页面结构

页面跟随系统深浅，底色取页面底；没有固定深色区。从上到下：

| 顺序 | 块 | 内容 | 什么时候出现 |
| --- | --- | --- | --- |
| 1 | 头部 | 漫画类型色 8% 淡底通栏（顶到状态栏）；左封面 112×150 圆角 12；右侧标题、作者行、徽章行（状态 / 分类 / 语言）、更新行（`latestText` · `updatedAt`）、「来源 · 主机名」；左上返回、右上收藏两个 40pt 圆按钮 | 一直；作者 / 徽章 / 更新行各自有数据才出 |
| 2 | 标签条 | 横向滚动的小胶囊（`tags`） | 有标签时 |
| 3 | 继续阅读 | 有历史：通栏卡片——上次页面缩略图 + 「继续阅读」+ 章节名 + 「第 13 页 · 昨天」（有页数时「13 / 45 页」+ 细进度条）；没有历史：通栏主按钮「从第 1 话开始读」（章节名解不出数字时「开始读 · 章节名」；只有一章「开始阅读」） | 章节加载完成且至少有一章时 |
| 4 | 简介 | 分区标题「简介」+ 正文三行折叠、点展开；下面是没落在头部的属性小字（发布 · 2021、许可…、`attributes`）与相册 / 二级页链接行 | 有 `description` 或有剩余属性 / 链接时 |
| 5 | 章节标题 | 分区标题「章节」+「N 章」，右侧「已读 M」小字（M > 0 时）与「正序 / 倒序」切换；贴顶 | 有章节时；正序 / 倒序只在 ≥ 2 章 |
| 6 | 分段芯片 | 胶囊芯片「1–50」「51–100」…（按显示顺序每 50 章一段），点了滚到该段首；与库页分类芯片同一种；跟分区标题一起贴顶 | ≥ 60 章时 |
| 7 | 章节目录 | 按标题形状二选一：纯编号 → 三列网格（格高 44）；带名 → 行列表（编号柱 + 标题 + 日期）；已读变淡、上次读到类型色标记、受限小锁、付费小币 | 有章节时 |
| — | 骨架 / 没有章节 / 取失败 | 见第八节 | 对应状态 |

下拉刷新重取详情并重读历史。页边距左右 20pt，分区标题 `footnote` bold 次级色。每一块都是有数据才出，没有的不留空位，也不用来源名或英文占位补空。

## 五、头部与作品信息

头部不再是模糊大图。它是一块漫画类型色 8% 的淡底通栏（浅色 #6D4FD6 淡化、深色 #B79CFF 淡化，都是 `accent` 的透明度，不是新色值），顶到状态栏，底边圆角 0；里面左封面右文字，文字随系统深浅。

| 位置 | 内容 | 取值 |
| --- | --- | --- |
| 封面 | 112×150、圆角 12、轻投影；走 `CoverImageView` 同一条封面管线，请求配置取规则的 detail 封面请求配置；detail `cover` 优先，没有用列表封面，再没有 `ComicDetailPlaceholder` | 左边距 20，上边距 = 安全区 + 56（给返回按钮留位） |
| 标题 | `title2` heavy 主文字色，最多三行 | 列表项标题优先，没有才用 detail `title` |
| 作者行 | `subheadline` 次级色，一行 | `author`；没有不出，不再用来源名填空 |
| 徽章行 | 状态（`status`）漫画类型色淡底 + 类型色字；分类（`category`）与语言（`language`）次级填充底 + 次级字 | 胶囊高 22、`caption` semibold；有几个出几个，一个都没有不出这行 |
| 更新行 | 「更新至第94话 · 2026-10-01」：`latestText` + `updatedAt`，有哪个写哪个，中间 · 分隔；`latestText` 照原文一行显示、超长截断 | `caption` 漫画类型色，前面一个小闪光图标；都没有不出 |
| 来源行 | 「来源名 · 主机名」 | `caption` 次级色；主机名取法与库页眉行相同 |
| 返回 | 左上 40pt 圆，卡片底 | 热区 44；固定在安全区顶，不随内容滚走 |
| 收藏 | 右上 40pt 圆，心形与库页封面爱心同一对图；已收藏实心用漫画 `accent` | 走 `ToggleFavoriteUseCase`，库页、收藏页跟着变 |

标签条（`tags`）在头部下方单独一行：横向滚动的小胶囊，`caption` 次级填充底，首尾留 20；没有标签不出。简介块与影视详情同一个：三行折叠、「展开 / 收起」；下面的属性小字按「发布 · 2021-03」「许可 · …」「编号 · …」「共 N 张」再加 `attributes` 的「label · value」排，相册与二级页是两行带箭头的链接；一条都没有就没有这块。

## 六、继续阅读

- **数据**：进页读本作品的全部章节历史（同来源、同 `comicItemID`），`visitedAt` 最近的一条是「上次读到」。它的 `chapterURL` 与哪一章相同就是那一章；对不上用章节名；都对不上（规则换过、站点改了地址）卡片仍写历史里的章节名，点了用历史记录直接开阅读器（`ReaderView` 的历史入口，与历史页点行同一条路）。
- **有历史 → 卡片**：通栏、高 88、圆角 18、卡片底、左侧 4pt 漫画类型色竖条。左：`lastPageImageURL` 的缩略图 56×72 圆角 8（阅读器已存过这张图，走同一条缓存；没有就用封面）。中：「继续阅读」`caption` bold 类型色；章节名 `subheadline` semibold；第三行 `caption` 次级「第 13 页 · 昨天 21:40」，有 `pageCount` 时「13 / 45 页 · 昨天 21:40」并在卡片底边画 3pt 进度条（类型色）。右：36pt 圆里一个书页图标，类型色底。整张卡可点。
- **没有历史 → 按钮**：通栏胶囊、高 50，漫画类型色底（浅 #6D4FD6 白字 / 深 #B79CFF 墨字 #141210）。文案「从第 1 话开始读」——起始章是按规则排序方向取的那一头（现有 `startingChapter`），数字从起始章标题解出，解不出写「开始读 · 章节名」；只有一章写「开始阅读」。
- **最新一话**：不再单设「Read Latest」按钮——倒序时最新一话就在目录第一格，正序时由分段芯片最后一段或「倒序」一点到达。
- **回来**：阅读器返回后重读历史（现有 `refreshLatestReadingHistory` 改为读全部），卡片文案、进度与目录的已读 / 上次读到标记跟着换。

## 七、章节列表

**标题解析与版式选择**（App 侧纯函数，只影响显示，不改顺序、不进存储）：从每条章节名开头解「第N话 / 第N章 / 第N回 / N話 / N话 / Chapter N / Ch.N / 纯数字 N」得到话数，紧跟着的「(n)」「（n）」「上 / 中 / 下」「前半 / 后半」是分节，编号柱写成「1-1」「3-上」；再去掉紧跟的分隔符（空格、冒号、全角冒号、间隔点），剩下的文字是「话名」。解数字时跳过开头的非数字前缀（sfacg 的「VIP」）。所有章节的话名都为空（允许少于 10% 的例外，如「番外」「预告」）就是**纯编号目录**，用三列网格；否则是**带名目录**，用行列表。按现有语料：MYCOMIC「第94话」与 sfacg「VIP第993话」走网格（VIP 前缀照原文显示，App 不删也不猜它的含义），patternrecognition「第1249话 乌云乌云别找我麻烦。」与めちゃコミック「1話(1):あるまじき瞳の色」走行列表（编号柱「1249」「1-1」）。

**三列网格**（纯编号）：

| 项 | 取值 |
| --- | --- |
| 格子 | 三列等宽、间距 10、高 44、圆角 12、卡片底；文字 = 原标题（「第94话」）`subheadline` semibold 主文字色，一行可缩到 0.8 |
| 与影视网格的区别 | 影视是最小宽 60 的自适应网格、只显示数字「01」；漫画是固定三列、显示整个标题，一屏约 36 章 |
| 已读 | 文字次级色、底换次级填充；右上一个 10pt 的小对勾次级色 |
| 上次读到 | 漫画类型色描边 1.5pt + 类型色字，左上一个小书签图标 |
| 受限 / 付费 | `isRestricted == true` 右上小锁，`isPaid == true` 右上小币；`nil` 不标 |

**行列表**（带名）：

| 项 | 取值 |
| --- | --- |
| 行 | 最小高 52、上下 10，行之间细分隔线从标题左缘起；整个目录装在一张圆角 18 的卡片底里 |
| 编号柱 | 宽 44，`subheadline` semibold 等宽数字次级色：解出数字写数字（「1249」「1-1」）；解不出写显示顺序的序号「#12」 |
| 标题 | 解出数字且话名非空 → 显示话名；否则显示原标题；`subheadline` semibold 主文字色，最多两行 |
| 日期 | `subtitle`（规则 `datetime` / `descriptionPath`）`caption` 次级色靠右；没有不出 |
| 已读 | 标题与编号都换次级色；右侧小对勾 |
| 上次读到 | 左缘 3pt 类型色竖条 + 类型色标题；右侧「第 13 页」（有页数「13 / 45」）代替日期 |
| 受限 / 付费 | 最右小锁 / 小币，`nil` 不标；不再写「Paid」字样 |

**排序与分段**：

- 默认显示顺序 = Core 给的顺序（规则 `sort` 已应用）。分区标题右侧「正序 / 倒序」点了翻转显示，不改进阅读器的导航顺序（`navigationOrder` 照旧）；不足 2 章不显示。
- ≥ 60 章时出分段芯片：按当前显示顺序每 50 章一段，芯片文字是段首与段尾的编号（「94–45」「44–1」，解不出编号用序号「1–50」）；点了滚到该段首行，列表仍是全量（不是筛选）；当前滚到哪一段哪个芯片选中。芯片与分区标题一起做贴顶分区头，样子与库页分类芯片 / 影视线路芯片同一个（`LibraryChipBar`）。
- 点一章：现有 `prepareToOpen`（受限 → 登录提示）再推入阅读器，不变。目录懒加载，不分页。

## 八、其余状态

| 场景 | 显示 |
| --- | --- |
| 正在取详情 | 头部先用列表项的标题、封面、`latestText` 画出来；继续阅读位置一条骨架胶囊；目录位置 8 行骨架（不知道版式前一律用行） |
| 取到了但没有章节 | 目录位置小空状态：列表图标 +「没有章节」+「这个来源没有给出任何章节」+「下拉重试」；没有继续阅读；头部、简介照常 |
| 取失败 | 同上，文案是错误原因，警示色三角；头部仍用列表项数据；不再弹系统警告框，也不再放「Try Again」按钮（刷新一律下拉） |
| 受限章节 | 点了走现有流程：没有登录页 / 已登录仍受限 → 说明文字；未登录 → 登录提示 → `SourceLoginView`。本轮只把两个系统 alert 换成页内横幅（警示色淡底，带「登录」按钮），文案与判断不动 |
| 下拉刷新 | 重取详情，历史一并重读 |
| 很长的目录 | sfacg 近 1000 章：三列网格约 28 屏，分段芯片 20 段横向滚动；懒加载，不预建按钮 |
| 深色模式 | 头部淡底、卡片、芯片、格子都随系统；继续按钮与选中芯片换深色取值（#B79CFF 底墨字） |

## 九、要追加的字段

**App 侧自己补的**（不经 fwq，不动 Core）：

| 字段 | 在哪 | 为什么 |
| --- | --- | --- |
| 本作品全部章节历史 | `ComicChapterHistoryRepository` 加按来源 + `comicItemID` 取全部的查询，`GRDBComicChapterHistoryRepository` 按现有唯一键的前三列查，经 `ReadingActivityPersistenceCoordinator` 给详情页 | 已读标记与「已读 M」计数；现有表、现有索引，不加列 |
| `ComicChapterHistory` 的 `pageCount`（可空 Int） | 模型与 `ComicChapterHistoryRecord` 加字段；`AppDatabaseMigrations` 追加一次迁移加列（`BCA-DB-001` 只追加）；`ReaderViewModel` 写历史时写 `pageImageURLs` 的个数；云同步 payload 不带（本机字段，合并时保留本机值） | 继续卡片「13 / 45 页」与进度条；没有就只写「第 13 页」 |
| 章节标题解析与版式判断 | `ComicDetailViewModel` 两个纯函数（解编号 + 分节 + 话名；判纯编号 / 带名），补单元测试 | 编号柱、网格 / 行二选一、分段芯片文字、「从第 1 话开始读」的数字 |
| 分段 | `ComicDetailViewModel` 按显示顺序每 50 章切段，段的 id 是段首章节 URL | 分段芯片与滚动目标 |
| 收藏 | `ComicDetailViewModel` 注入 `ToggleFavoriteUseCase`（`LibraryFeatureFactory`） | 右上爱心，与库页 / 影视详情同一条 |
| 上次页面缩略图 | 读现有 `lastPageImageURL`（带 `lastReaderPageURL` 作 referer）走阅读器同一条图片管线 | 继续卡片左侧；不加字段 |

**向 fwq 提的**（定义点在 fwq，这里只写引用点；正文在上面链接的 fwq 需求文本，App 侧对应 `APP-MEMO-030`，实施与部署状态见 fwq 的状态表）：
detail 的 author / status / category / tags / description / updatedAt → `BC-COMIC-160`（Core `DetailFields`，Core 不改）；
sfacg 链接内的受限标记 → `BC-COMIC-147` 2026-10-08 修订（交付 `restriction`，**章节标题保留「VIP第N话」原样**——用户 10-08 裁定 VIP 是「要登录才能看」的证明；App 的标题解析要容忍编号前的前缀，按 `BC-COMIC-121` 不按字样猜受限）；
列表 `latestText` → `BC-LIST-128`（不是「更新到哪」的不交付，没有就不出更新行）；
章节 `datetime` → 不生成（语料只约 3 个主机行内有日期，结论记在 `BC-COMIC-147` 2026-10-08 修订末段）。App 侧的实施不等 fwq。

**候选、本轮不做**：Core 把 `ChapterRule.section` 的 `title` 透传成 `SourceChapter` 的分组名——现有规则的 section 都没有标题，等 fwq 生成带标题的分组再做（2026-10-08 用户裁定 fwq 本轮不做：归档漫画作品页多分组为零）；HTML `ChapterRule` 加 `paid` / `paidValues`——2026-10-08 用户裁定**不加**（匿名只能验证「打不开」，按 `BC-COMIC-121` 走 `restriction`）；「全部标记已读 / 清除记录」要进删除来源连带清理与云同步范围，单独立项。

## 十、视觉取值

不新增颜色，全部已在 `CatalogStyle.swift`：

| 项 | 取值 |
| --- | --- |
| 头部淡底 | 漫画 `accent` 8%（`CatalogKindStyle.of(.comic).accent` 的透明度） |
| 继续按钮、选中分段芯片、上次读到、继续卡片竖条与进度条、更新行、已收藏爱心 | 漫画类型色：浅 #6D4FD6 / 深 #B79CFF；底上的字浅色白、深色 #141210（`bannerIconInk`） |
| 状态徽章 | `accent` 12% 底 + `accent` 字；分类 / 语言徽章与标签 `fillBackground` 底 + 次级字 |
| 页面底 / 卡片底（目录卡、格子、继续卡片、圆按钮）/ 次级填充（已读格子、未选芯片） | `pageBackground` / `cardBackground` / `fillBackground` |
| 受限横幅、取失败 | `warning` / `warningFill`，圆角 16 |
| 尺寸 | 封面 112×150 圆角 12；圆按钮 40（热区 44）；继续卡片高 88 圆角 18、缩略图 56×72；继续按钮 50 胶囊；芯片高 36；网格三列、格高 44、圆角 12、间距 10；行最小高 52、编号柱宽 44；页边距 20 |
| 字号 | 标题 `title2` heavy；作者 `subheadline`；徽章 / 更新行 / 来源行 / 日期 `caption`；分区标题 `footnote` bold；格子与行标题 `subheadline` semibold；简介 `subheadline` |

## 十一、裁定

2026-10-08 用户裁定九项全取 A：浅色「封面 + 信息」头部；目录版式按标题形状自动选；≥ 60 章出分段芯片、点了滚到段首；读本作品全部章节历史做已读标记；历史表追加 `pageCount`；有历史用卡片、没历史用按钮；受限与失败提示换页内横幅；右上收藏；向 fwq 提生成覆盖需求。核对线上目录后补的一条：更新行照 `latestText` 原文显示一行，内容对不对由 fwq 修。

## 十二、不改的东西

- 章节的解析与顺序（Core / Runtime，含章节自身分页的聚合）、`prepareToOpen` / 登录后刷新的判断、阅读器与历史写入的路径（只多写一个 `pageCount`）、`navigationChapterURLs` 的携带、四个入口。
- App 不提供规则创建或编辑入口（`BCA-UI-003`）；页上有什么由规则决定。

## 十三、实现位置

- `BrowseCraft/Features/Library/Comic/Detail/ComicDetailView.swift` 与 `ComicDetailSections.swift`：头部、标签条、继续卡片 / 按钮、简介折叠与属性小字、受限横幅、骨架与空 / 失败态；原来的动作卡、信息卡与共用卡片容器三个视图随之删去。
- `BrowseCraft/Features/Library/Comic/Detail/ComicDetailChapterSection.swift`：贴顶分区头（计数、已读、正序 / 倒序、分段芯片）、三列网格与行列表两种版式、已读 / 上次读到 / 受限 / 付费标记。
- `BrowseCraft/Features/Library/Comic/Detail/ComicDetailViewModel.swift`：标题解析、版式判断、显示顺序、分段、本作品全部历史与继续目标、已读集合、收藏切换、属性摆位。
- `BrowseCraft/App/Composition/LibraryFeatureFactory.swift`：注入收藏用例。
- `BrowseCraft/Domain/Repositories/ComicChapterHistoryRepository.swift`、`BrowseCraft/Infrastructure/Database/Repositories/GRDBComicChapterHistoryRepository.swift`、`BrowseCraft/Application/UseCases/History/ReadingActivityPersistenceCoordinator.swift`：按作品取全部章节历史。
- `BrowseCraft/Domain/Models/History/ComicChapterHistory.swift`、`BrowseCraft/Infrastructure/Database/Records/History/ComicChapterHistoryRecord.swift` 与其 schema 扩展、`BrowseCraft/Infrastructure/Database/Migrations/AppDatabaseMigrations.swift`、`BrowseCraft/Features/Library/Comic/Reader/ReaderViewModel.swift`：`pageCount`。
- `BrowseCraft/Features/Library/Components/LibraryListTabBar.swift`：`LibraryChipBar` 复用，不改。
- 三份 `Localizable.strings`：继续阅读四种文案、「章节」「N 章」「已读 M」「N / M 页」「正序 / 倒序」「没有章节」、受限横幅；删去只剩本页在用的「Loading Details / Paid / About / Information / Try Again / Access Required / Photo Album / Related Page / ID / Info」与旧的空章节说明（「Continue Reading」「Chapters」「Log In」「Not Now」别处还在用，保留）。
