# 库页书籍库的视觉与信息结构重设计

设计稿（画布，含台灣小說網形态、Royal Road 多分类、Loyal Books 整站有声、深色、长按菜单、骨架、空、失败、尺寸与取值、即梦设定，共 10 张）：
[库页书籍库重设计](https://claude.ai/artifact/HBPzWHJ8v8rWaLrXQnNJqm)；设计文档：[库页书籍库重设计](https://claude.ai/artifact/3nnvDue2rGog4EMxqfwbCk)。
设计与实施状态见 [STATUS.md](../STATUS.md)。外壳（眉行、大标题、圆按钮、贴顶芯片、各状态、分页脚）与颜色、圆角、字号沿用
[库页视频库](Library-Video-Page-Redesign-Design.md)，「上次读到」瓷砖与「读到哪」的取法沿用 [库页漫画库](Library-Comic-Page-Redesign-Design.md)，本页不新增色值。

## 一、背景

书籍库是库页三种类型里最后一个还在用旧卡片的。漫画库那轮把重设计前漫画与书籍共用的三列封面卡原样挪成旧卡片 BookLibraryCardView（本轮删除）给书籍继续用：
封面圆角 6、12pt 粗体标题、写死的蓝紫色最新章、每张封面右上一个黑圈爱心、标题颜色还引着 `libraryTitleText`。外壳已经是三类共用的，本轮不动。

书和影视、漫画的不同，决定了它不该再是封面墙：

- 书靠标题识别，不靠封面。文字书站的封面小、粗糙、经常没有（规则里 `cover` 可选，作品页封面还被 ATS 拒过），三列封面墙下标题只剩两行被截断的字。
- 书是逐章追的，追的单位比漫画还细。「读到第 312 章」「最新第 1049 章」是回到库页最常问的两件事，两行小字挤在封面下写不下。
- 读书 kind 还包含有声书。reader 规则每条恰好一个 `variant`（`text-dom | text-api | audio-media`），有声作品走 Readium Audio Navigator 与 `AudiobookPlayerView`；列表页现在对此一无所知。
- 「上次看到 / 读到」瓷砖只接了视频与漫画历史，读书来源上永远不出。

所以书籍库用一行一本的书脊列表：左边一张小封面，右边书名、最新章、读到哪，文字有地方写全；有声书同一版式，用耳机标记与「听到」措辞区分。
视频两列海报墙、漫画三列封面墙、书单列书脊行——三种密度、三种识别方式，就是三种版式。

## 二、规则与本机实际给什么数据

页上每一块只在规则或本机给了数据时出现。读书列表解析器（Core `DefaultBookRuleParser.parseList`）只读四个键，规则里多声明的字段会被忽略；
七份能找到的真实规则（fwq 生成产物与 App 测试夹具：台灣小說網、novels.com.tw、嗶哩輕小說、Royal Road、笔趣阁、SF轻小说、Loyal Books）逐条核过。

**列表项**（`ContentItem`，`id` = 详情地址）：

| 字段 | 规则里的来源 | 七份规则的现状 | 页面怎么用 |
| --- | --- | --- | --- |
| 标题 | `title`，必有 | 都有 | 行标题，最多两行 |
| 封面 | `cover`，可选 | 七份都声明了；文字站封面小、粗糙 | 左侧小封面 60×80；取不到退回 `BookCoverPlaceholder` |
| 详情地址 | `detailURL`，必有 | 都有 | 点行进站点书详情；也是和收藏、历史对上的键 |
| 最新章 | `latestText`，可选 | 台灣小說網、novels、嗶哩輕小說、Royal Road 有；笔趣阁、SF轻小说、Loyal Books 没有 | 「最新 · 原文」一行，类型色；没有整行不出 |
| 编号 | `idCode` | 两份声明了，解析器不读 | 不显示 |
| 作者 | 列表规则不给；详情合同允许 `author`，七份没有一份声明 | 没有 | 不显示，本轮不留位 |

**有声书在列表层没有任何标记。** App 是进了详情、按章节地址扩展名判断出 `isAudiobook` 的。来源级有现成的事实：
`BookSourceConfiguration.rule.ruleSets.readerRules[].contentType`——Loyal Books 全是 `audio`，其余六份全是 `text`。
规则合同允许一个来源同时有 text 与 audio 两种 reader 规则，那种站列表层判不出。所以列表页能知道的是三档：整站有声 / 整站文字 / 混合（不标）。

**本机阅读历史**（`BookReadingHistory`，一本书一条）：书名、封面、`chapterTitle`、`chapterURL`、`visitedAt`、`bookItemID`（= 详情地址）。
只记到章节一级，没有页数、百分比、播放时间；全书进度在 `book_reading_progress.totalProgression`（0…1，文字书与有声书都写），按 `bookID`
（`SiteBookIdentity` 由来源 ID 与详情地址生成）取。

**收藏**：`favoriteItemIDs` 对书生效。**其他外壳数据**与视频库同一取法：分类芯片看列表页个数（嗶哩輕小說 5、Royal Road 7）；搜索按钮看有无搜索页
（Royal Road、笔趣阁、SF轻小说）；账号按钮看 `site.loginURL`；分页脚看 `pagination.urlTemplate`（七份都有）。

模拟器上现在没有读书来源（茶香言情網为给漫画腾位置删了，规则只在线上）；走查时从目录重新加，有声书只能用 Loyal Books 夹具或等线上有有声来源。

## 三、入口、相邻页面与范围

- **入口**：底栏第三个标签「库」，当前来源是读书 kind 时走本版式；来源页点来源、收藏页与历史页「在库中查看来源」都落到这里。
- **出口**：点行进站点书详情 `BookSiteDetailView`；「上次读到」瓷砖与行长按「继续读」用历史直接开 `BookReaderView`（`SiteBookChapterSelection(history:source:)`，
  不带章节、按续读位置接着），与历史页点行同一条路；文字书进 EPUB 阅读器、有声书进播放器，分流在阅读器里按 manifest 做；左上搜索弹出来源内搜索页（结果复用本页的行）；账号按钮打开来源登录页。
- **相邻**：左邻收藏页、右邻历史页，历史页的书行就是「小封面 + 书名 + 读到哪」，本页的书脊行和它同一种形状。本页的绿色只用在眉行图标、最新章、读到哪、已收藏爱心、瓷砖和选中芯片上。
- **范围**：只改当前来源是读书 kind 时的正文——书脊列表、行、「上次读到」瓷砖、骨架与空态插画，外加读书历史与进度的只读查询、来源级「整站有声」派生值。
- **不在范围**：站点书详情页（另立项，仍是系统 `List`）、阅读器与播放器样式、本地书导入、搜索页外壳、列表数据与分页、底栏（系统 `TabView`，五页共用）。

## 四、页面结构

页面跟随系统深浅，底色取页面底，隐藏系统导航栏。从上到下（1、2、4、6 与视频库同形，只换类型色）：

| 顺序 | 块 | 内容 | 什么时候出现 |
| --- | --- | --- | --- |
| 1 | 顶部 | 眉行「书 书籍 · 主机名」（`book.closed.fill` 取书籍类型色；整站有声时「有声书 · 主机名」、图标换 `headphones`）+ 大标题 = 来源名 + 右侧搜索 / 账号圆按钮 | 一直；两个按钮各自按规则有无 |
| 2 | 分类条 | 贴顶胶囊芯片，选中段书籍类型色底 | 来源有两个以上列表页时 |
| 3 | 上次读到 | 书籍类型色的深色瓷砖：封面 72×100、「上次读到」/「上次听到」、书名、章节名、全书进度条、时刻；点了直接开阅读器 / 播放器 | 当前来源有读书历史时 |
| 4 | 分类出错横幅 | 警示色淡底一行 | 有内容但当前分类报错时 |
| 5 | 书脊列表 | 单列、一行一本：左封面 60×80 圆角 8，右侧书名两行、最新章一行、读到哪一行；行间分隔线；行尾已收藏小爱心 | 有内容时 |
| 6 | 分页脚 | 列表下方一行小字 | 规则支持分页且有内容时 |
| — | 骨架 / 空 / 失败 / 切源 | 见第七节 | 对应状态时整页只出一种 |

下拉刷新、滑到底加载下一页两条路不变。页边距左右 20pt。一屏约 7 本。

## 五、书脊行

一行 = 左封面 + 右侧三行文字 + 行尾标记；行高由封面 80pt 定，上下各 10pt。没读过、没收藏的行只有书名和最新章。

| 位置 | 内容 | 取值 |
| --- | --- | --- |
| 封面 | 60×80（3:4），`ItemThumbnailImageView` 走现有封面管线，请求配置取规则的图片请求配置；无封面退回 `BookCoverPlaceholder` | 圆角 8，左侧压 2pt 书脊线（黑 18%）；不描边不投影 |
| 封面右下 · 耳机 | 整站有声时每行压 `headphones` 小圆；文字站与混合站不压 | 20pt 黑 40% 圆里 11pt 白图标，离边 4 |
| 第一行 · 书名 | `title`，`subheadline` semibold 主文字色，最多两行 | 行距 4 |
| 第二行 · 最新章 | `latestText` 照原文一行截断，前缀「最新 · 」；`footnote` 书籍类型色 | 没有不出，下面的行上移 |
| 第三行 · 读到哪 | 本机历史有这本时「读到 · 章节名」（整站有声「听到 · 章节名」），章节名照 `chapterTitle` 原文一行截断，不缩编号（各站编号形式不一：章 / 卷 / 話 / Chapter）；`footnote` 次级色，前面一个 6pt 类型色圆点 | 没读过不出 |
| 行尾 · 已收藏 | 只在已收藏时显示 `TabFavorites` 14pt 实心书籍类型色，垂直居中；未收藏不占位 | 收藏 / 取消走长按菜单 |
| 分隔 | 行与行之间 0.5pt 分隔线，从文字左缘起（缩进 72），最后一行没有 | 系统 `separator` |
| 整行 | 点 = 进站点书详情；长按菜单「打开」「收藏 / 取消收藏」，读过的再加「继续读 · 章节名」（整站有声「继续听 · 章节名」）直接进阅读器；预览按整行圆角 12 裁 | 按下整行底色变 `fillBackground` |

- 文字有三行的位置，长书名能写全两行，最新章和读到哪各自一行不互相挤；这是和封面墙的第一个区别。
- 读到哪放在文字里而不是压在封面上：封面只有 60pt 宽，压一个胶囊会盖掉半张图。
- iPad 与横屏：宽过 700pt 时变两列，行构造不变。搜索结果复用同一行（搜索页不接阅读器，长按没有「继续读」）。

## 六、「上次读到」瓷砖

与视频库「上次看到」、漫画库「上次读到」同一张 `HistoryContinueTileView`，换书籍的来源瓷砖样式（底 #152A26、光圈与小字 #5CC8B0、次文字 #B6DDD3）。

- **条件**：当前来源的读书历史里取 `visitedAt` 最近一条；切来源重取，从阅读器 / 播放器 / 详情页回来、回到库标签、来源页连带删除历史之后刷新（与视频、漫画瓷砖同一组时机）。属于来源、不属于分类。
- **样子**：左封面 72×100 圆角 12（历史里的 `coverURL`，退回 `BookCoverPlaceholder`）；右侧小字「上次读到」，整站有声时「上次听到」；书名 `headline` bold 两行；
  第三行章节名照原文（没有 `chapterTitle` 这行不出）；4pt 进度条写全书进度（`totalProgression`，没有不画）；底行只写时刻。
- **点击**：整张瓷砖 = 用历史直接开 `BookReaderView`（不带章节，按续读位置接着，有声书到播放器），与历史页点行同一条路径；长按菜单「继续读 / 继续听」「打开作品」（进详情）。不在这里删历史。
- **不出现**：没有读书历史、来源切换中、搜索页。骨架 / 空 / 失败态下有历史照样显示。
- **数据**：`LibraryViewModel` 加读读书历史的只读查询，一次按来源取全部（一书一条）：瓷砖取最近一条，行的「读到哪」按 `bookItemID` 查字典；
  进度条另读一次 `BookReadingProgressRepository`（只读瓷砖那一本，不逐行查）。「打开作品」要的列表条目直接用历史里的详情地址、书名、封面拼（书的 `item.id` 就是详情地址）。

## 七、其余状态

正文同一时刻只出一种版面（`LibraryBodyState` 不动）；眉行、大标题、分类条与「上次读到」瓷砖在所有状态下照常。

| 场景 | 显示 |
| --- | --- |
| 首屏加载 | 骨架与书脊行同形：左 60×80 色块 + 右三条（长、中、短），呼吸动画；`LibrarySkeletonGridView` 加 `.bookList` 形态，7 行 |
| 取回来是空的 | `LibraryPlaceholderView`：插画 `EmptyStateLibraryBook`（看板娘坐在三本淡色精装书上、膝上翻开一本空白的书；文字书与有声书共用）+「还没有内容」+ 一句说明 +「下拉可重新载入」 |
| 第 1 页失败 | 同上，插画 `EmptyStateOffline` +「载入失败」+ 错误原因 +「下拉重试」 |
| 有内容但本分类报错 | 警示色淡底横幅，在列表上方（现有 `LibraryTabErrorBanner`） |
| 切换来源 | 旧列表留在屏上盖页面底 82% + 居中状态卡（现有） |
| 翻页中 / 还有下一页 / 已到底 | 分页脚三条文案（现有） |
| 下拉刷新 | 系统下拉控件；刷新中列表不换骨架 |
| 来源需要登录 | 账号按钮空心；列表照规则给的结果显示（现状） |
| 深色模式 | 页面底、分隔线、芯片随系统；瓷砖是固定深色取值，两种模式下一样；类型色切到 #5CC8B0 |

空状态插画与其余插画同规格（同一个看板娘、即梦出图、透明底、540px 高、按 180pt 显示，画面内不含文字）；即梦设定与提示词在画布「书籍库空状态插画 · 即梦设定」画板，已出图入库（构思 A「坐在书堆上翻开空白的书」）。

## 八、每个元素的数据来源与缺省

每个元素都是有数据才显示，没有就整块不出、不留空位。

| 元素 | 数据来源 | 没有时 |
| --- | --- | --- |
| 封面 | 列表规则 `cover` | 退回 `BookCoverPlaceholder` |
| 书名 | 列表规则 `title` | — |
| 最新章 | 列表规则 `latestText` | 整行不出 |
| 读到哪 | 本机读书历史按 `bookItemID` | 整行不出 |
| 耳机、「听」措辞 | 来源配置 reader 规则全 `audio` | 按文字书措辞、不压耳机 |
| 已收藏爱心 | `favoriteItemIDs` | 不出 |
| 「上次读到」瓷砖 | 本机读书历史最近一条；进度条取进度表 | 不出；没有进度不画进度条 |
| 分类芯片 | 列表页个数 ≥ 2 | 不出 |
| 搜索按钮 | 规则有搜索页 | 不出 |
| 账号按钮 | 来源有 `loginURL` | 不出 |
| 分页脚 | 规则支持分页 | 不出 |

`latestText` 照原文显示：各站抓到的原文形式不一，有的可能自带「更新至」「最新章节：」之类前缀，与「最新 · 」重复时属于规则正规化（fwq 侧），App 不改规则。

## 九、要追加的字段与查询

不加表、不加列、不动 Core 与规则；只加两个只读查询和一个来源级的派生值。

| 项 | 在哪 | 为什么 |
| --- | --- | --- |
| 按来源取全部读书历史 | `LibraryPersistenceCoordinator` 加可选的 `BookReadingHistoryRepository`（现有 `fetchHistory(userID:)` 按 `sourceID` 筛，`visitedAt` 倒序）；`LibraryViewModel` 存「最近一条」与按 `bookItemID` 的字典，与视频 / 漫画瓷砖同一组刷新时机 | 瓷砖与行的「读到哪」；一次读全部，不按行逐条查 |
| 瓷砖那一本的全书进度 | 同一个协调器加可选的 `BookReadingProgressRepository`，按 `SiteBookIdentity` 取一条的 `totalProgression` | 瓷砖进度条；只读一本 |
| 整站是否有声 | `ResolveLibrarySourcePresentationUseCase` 按 `rule.ruleSets.readerRules` 算：全 `audio` → 有声；否则按文字措辞 | 眉行、封面耳机、「听到 / 上次听到 / 继续听」措辞 |
| 阅读器入口 | `LibraryView` 加一条「用历史开 `BookReaderView`」的导航（`SiteBookChapterSelection(history:source:)`，历史页已在用） | 瓷砖与长按「继续读」 |

**向 fwq 提的（候选，不堆本轮）**：作者。规则合同允许详情 `author`，七份规则没有一份声明，列表规则没有这个键；列表页要显示作者，得列表合同加 `author`
可选字段 + Core 解析器多读一个键 + 生成器覆盖，三头都要动。本轮不留位，等规则给了再立项。

**候选、本轮不做**：有声书的播放时间（要解 `locatorJSON` 里的 Locator，历史页也没做，两页一起立项）；「有更新」红点等有了可比的 `latestText` 再说。

## 十、视觉取值

不新增颜色，全部已在 `CatalogStyle.swift`：

| 项 | 取值 |
| --- | --- |
| 书籍类型色（随系统） | 浅 #1E7D68 / 深 #5CC8B0：眉行图标、选中芯片底、最新章小字、读到哪的圆点、已收藏爱心（`CatalogKindStyle.of(.book).accent`） |
| 书籍固定深色取值 | 底 #152A26、强调 #5CC8B0、次文字 #B6DDD3、墨 #141210：瓷砖（`bannerBackground` / `bannerAccent` / `bannerSecondaryText` / `bannerIconInk`） |
| 页面底 / 卡片底 / 按下底 | `pageBackground` / `cardBackground` / `fillBackground` |
| 分隔线 | 系统 `separator` |
| 警示 | `warning` / `warningFill`：分类出错横幅 |
| 圆角 | 瓷砖 24、封面 8（瓷砖内 12）、横幅 16、长按预览 12、芯片胶囊 |
| 尺寸 | 页边距 20；行内边距上下 10、封面与文字间距 12；封面 60×80；耳机圆 20、离边 4；读到哪圆点 6；顶部按钮圆 40；芯片高 36；瓷砖封面 72×100 |
| 字号 | 大标题 `largeTitle` heavy；眉行 `caption`；芯片 `subheadline`；书名 `subheadline` semibold；最新章与读到哪 `footnote`；分页脚 `footnote` 次级色 |

## 十一、裁定

2026-10-09 用户裁定十项全取 A：单列书脊行；封面 60×80 带书脊线；来源级判有声（耳机 + 眉行 +「听」措辞，混合站不标）；读到哪放文字第三行；加「上次读到」瓷砖含全书进度条；
作者本轮不留位；只在已收藏时行尾小爱心、动作走长按；长按加「继续读 / 继续听」；本轮出空状态插画 `EmptyStateLibraryBook`；骨架与书脊行同形。
画稿时改了一处措辞并记入设计文档：「读到 ·」与瓷砖第三行写章节名原文一行截断，不缩成「第 N 章」。

## 十二、不改的东西

- 列表数据、分页、分类缓存、切换来源、收藏切换、搜索、登录与凭据；`LibraryBodyState` 五种状态与优先级；下拉刷新与触底加载两条路。
- 视频库与漫画库；站点书详情页、EPUB 阅读器与有声书播放器；本地书导入；搜索页外壳；底栏（系统 `TabView`，不随来源类型变）。
- App 不提供规则创建或编辑入口（`BCA-UI-003`）；`latestText` 等字段有无由规则决定。

## 十三、实现位置

- `BrowseCraft/Features/Library/Book/Site/BookLibraryRowView.swift`：新建书脊行（封面 + 书脊线 + 耳机 + 三行文字 + 行尾爱心 + 长按菜单）；旧卡片 `BookLibraryCardView.swift` 删除。
- `BrowseCraft/Shared/UI/LibraryTitleColor.swift`：最后一个引用随旧卡片消失，一并删。
- `BrowseCraft/Features/Library/Components/LibraryContentView.swift`：书籍分支换成单列 `LazyVStack` + 分隔线，给行传读到哪、是否有声与「继续读」回调。
- `BrowseCraft/Features/Library/LibraryView.swift`：「上次读到」瓷砖的书籍分支与用历史开 `BookReaderView` 的导航；眉行措辞；骨架与空态按类型选。
- `BrowseCraft/Features/Library/LibraryViewModel.swift` 与 `LibraryPersistenceCoordinator`：读书历史与进度的只读查询、最近一条与按书的字典、刷新时机；`LibraryFeatureFactory` 接 GRDB 仓储。
- `BrowseCraft/Application/UseCases/Library/ResolveLibrarySourcePresentationUseCase.swift`：整站是否有声。
- `BrowseCraft/Features/Library/Components/LibrarySkeletonGridView.swift`：加 `.bookList` 形态。
- `BrowseCraft/Features/History/Components/HistoryEntryRowView.swift`：`HistoryContinueTileView` 加可选的标题文案，「上次听到」由调用方传。
- 三份 `Localizable.strings`：「最新 · %@」「读到 · %@」「听到 · %@」「上次听到」「继续听 · %@」「有声书」；其余沿用。
- 资产：`EmptyStateLibraryBook`（已入库并登记预算）。
