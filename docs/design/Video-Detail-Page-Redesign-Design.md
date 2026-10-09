# 影视详情与选集页的视觉与信息结构重设计

设计稿（画布，含连续剧有历史、电影四线路、樱花动漫实际效果、深色、正在取详情、没有选集、取失败、正在解析、解析失败、尺寸与取值，共 10 张）：
[影视详情与选集页重设计](https://claude.ai/artifact/UvKoGH47UHKVhivdPLmVoh)；设计文档：[影视详情与选集页重设计](https://claude.ai/artifact/FQ2EUHAkYGjeWsfB6KtYWB)。
设计与实施状态见 [STATUS.md](../STATUS.md)。颜色、圆角、字号与交互约定沿用库页视频库、来源页与历史页
（[库页视频库](Library-Video-Page-Redesign-Design.md)、[来源页](Sources-Page-Redesign-Design.md)、[历史页](History-Page-Redesign-Design.md)），本页不新增色值。

## 一、背景

`VideoDetailView` 是点海报进入的页：头图 + 一张「简介 / 最近 / 信息」三行卡 + 一列扁平的选集行。库页改完之后这一页最显旧：

- 头图是海报被拉成 1.05 倍屏宽的方块，2:3 的海报上下被裁掉，标题压在模糊的海报上读不清。
- 「简介」一行写的是来源名——规则没给 `description` 时用来源名填空，等于把「没有」写成了一句假话；「最近 Unknown」是列表没给 `latestText` 时的英文占位。
- 「信息 地区: 喜剧」：规则的 metadata 标签是「地区」，取到的却是类型，页面照单全收。
- 选集是一列带 › 的行：四条线路各一集的电影按行摆，看不出哪些是同一集的不同片源；二十集的连续剧要滚二十行。
- 看到第几集、上次看的是哪一集，页上没有；要接着看只能去历史页。没有收藏入口。

## 二、规则实际给什么数据

页面只能画规则真给的东西。下面按 Core 的运行期模型和三个已发布视频来源的规则（樱花动漫、威视TV、看片狂人）逐字段核对。

**详情**（`SourceDetailOutput.metadata`，规则 `detailRules.fields`）：

| 字段 | 规则里的来源 | 现状 | 页面怎么用 |
| --- | --- | --- | --- |
| 标题 | detail `title`（必有） | 三个都有；低端影视取到的是带 SEO 后缀的页面标题 | 大标题用列表项的标题（用户点进来时看到的名字），列表没给时才用 detail `title` |
| 封面 | detail `cover`（可选） | 樱花、看片狂人有；威视没有 | 头图；没有就用列表项带进来的封面，再没有退到占位图 |
| 简介 | detail `description`（可选） | 樱花没有；威视取 `meta description`；看片狂人取 `.vodbox` | 简介块，没有就不出；不再用来源名填空 |
| 元数据 | detail `metadata[]`，每条 `{id, label, value}`；Core 转成 `SourceDetailAttribute` 时此前只留 label + value，`id` 丢了 | 樱花 1 条（label「地区」，取到的其实是类型）；威视 2 条（语言、「更新：」）；看片狂人 0 条 | 元数据行，只显示非空的；`key` 透传之后按 key 定位置（第九节） |
| 更新状态 | 列表项带进来的 `ContentItem.latestText` | 樱花没有；威视、看片狂人有 | 状态徽章，没有不出 |
| 年份、评分、导演、演员、时长、总集数、更新时间 | 规则 schema 里没有这些字段，只有 `metadata[]` 能装 | — | 不给固定位；有对应 key 的 metadata 才显示 |

**选集**（`SourceDetailOutput.chapters`，每条 `SourceChapter`；规则 `episodeRules`）：

| 字段 | 规则里的来源 | 现状 | 页面怎么用 |
| --- | --- | --- | --- |
| 集名 | episode `title`（必有） | 「第01集」「HD中字」「正片」…站点原文 | 集号格子的字；能解出数字的缩成「01」，解不出的整串显示 |
| 线路 | group `title` 或 `titleStrip` → `SourceChapter.subtitle`；没有分组时为 nil；App 侧已有「首集标题重复就切成线路 1 / 2」 | 看片狂人有分组；樱花、威视没有——樱花电影的四条线路各一集被接成四条「集」，首集标题不重复所以没被切开 | 线路芯片；只有一条线路不出芯片 |
| 播放页地址 | episode `playURL`（必有） | 都有 | 点集解析播放；也是和历史对上「上次看的哪一集」的键 |
| 序号 | episode `order`（可选），只用于排序 | 三个都没有 | 不显示 |
| 受限 / 付费 | episode `restriction` / `paid` → `isRestricted` / `isPaid` | 三个都没有 | 为 true 才在格子上标小锁 / 小币；nil 不标 |
| 单一播放动作 | `videoPlaybackAction`（没有选集时） | — | 当作只有一集 |
| 集的封面、时长、日期 | 规则 schema 里没有 | — | 不画 |

**历史**（本机 `video_watch_history`，一部作品一条）：`vodID`、`sourceIndex`、`episodeIndex`、`episodeKey`、`episodeTitle`、`playPageURL`、`lastPlaybackTime`、`duration`、`updatedAt`，按来源 + `detailURL` 能找到本作品的那一条。足够画「继续看 第 N 集 · 看到 23:14」和高亮上次看的集号；历史一部作品只存最近一集，所以只能标一集。

## 三、入口、相邻页面与范围

- **入口**：库页海报、搜索结果、收藏页行、历史页与库页「上次看到」瓷砖长按「打开作品」，都推入本页；进入后隐藏底栏，左上返回。
- **出口**：点一集或「继续看」开全屏播放器（`VideoPlayerHostView`，播放器自己有上一集 / 下一集）；播放器关闭回本页，本页重读历史。
- **相邻**：上一页是库页（海报墙、琥珀芯片、深色瓷砖）。本页的头图就是那张海报，集号格子和线路芯片沿用库页的芯片语言，继续看按钮用视频类型色。
- **范围**：详情页三种类型各用一种版式——视频是「海报 + 线路 + 集号网格」，漫画和书籍各自另立项。本文定视频详情页的全部：头图、标题区、继续看、简介、线路与选集、收藏、各状态，外加为了把数据摆对位置要追加的字段（第九节）。
- **不在范围**：播放器、播放解析、选集的去重与切线路逻辑（`filteredEpisodeChapters` 不动）、规则本身。

## 四、页面结构

页面跟随系统深浅，底色取页面底；头图区是固定深色（海报模糊放大再压暗），与库页的深色瓷砖同一种做法。从上到下：

| 顺序 | 块 | 内容 | 什么时候出现 |
| --- | --- | --- | --- |
| 1 | 头图区 | 背景：海报放大模糊 + 黑 45% + 底部渐变到页面底，顶到状态栏；前景：左海报 108×162 圆角 14，右侧标题、元数据行、状态徽章、「来源 · 主机名」；左上返回、右上收藏两个 40pt 圆按钮 | 一直；没有封面时背景是视频深色底 #2B2117，海报位用占位图 |
| 2 | 继续看 | 通栏主按钮：有历史「继续看 · 第 12 集」+ 小字「23:14 / 45:00」；看到 95% 以后且有下一集「下一集 · 第 13 集」，没有下一集「再看一遍 · 第 12 集」；没有历史「从第 1 集开始看」（集名解不出数字时「开始看 · HD中字」）；单集没有历史「播放」、有历史「继续看」不带集名（集名往往就是页面标题） | 选集加载完成且至少有一集时 |
| 3 | 简介 | 分区标题「简介」+ 正文三行折叠、点展开；下面是没有落在元数据行里的 metadata（「导演 · xxx」或 label: value） | 有 `description` 或有剩余 metadata 时 |
| 4 | 选集标题 | 分区标题「选集」，右侧「N 集 · 正序 / 倒序」 | 正序 / 倒序只在当前线路 ≥ 2 集时 |
| 5 | 线路芯片 | 胶囊芯片，高 36，选中段视频类型色底，与库页分类芯片同一种；默认选中含上次看的那一集的线路，没有历史选第一条 | 两条以上线路时 |
| 6 | 集号网格 | 自适应网格：每格最小宽 60、高 44、圆角 12、卡片底；数字集名等宽排整齐，非数字按内容加宽；上次看的那一集类型色描边 1.5pt + 类型色字 + 左上小播放三角；受限 / 付费右上小锁 / 小币 | 有选集时 |
| — | 骨架 / 没有选集 / 失败 / 解析中 | 见第八节 | 对应状态 |

下拉刷新重取详情并重读历史。页边距左右 20pt，分区标题 `footnote` bold 次级色。每一块都是有数据才出，没有的不留空位，也不写 Unknown。

## 五、头图与标题区

| 位置 | 内容 | 取值 |
| --- | --- | --- |
| 背景 | 同一张海报铺满、模糊半径 30、压黑 45%，底部 80pt 渐变到页面底；高度 = 安全区 + 236 | 固定深色，浅深模式一样；没有封面时纯色 #2B2117 |
| 海报 | 108×162、圆角 14、轻投影；走 `ItemThumbnailImageView`，请求配置取规则的图片请求配置；规则的 detail `cover` 优先，没有用列表封面，再没有 `VideoDetailPlaceholder` | 左边距 20，底边与标题区底对齐 |
| 标题 | `title2` heavy，最多三行，固定浅色字 #F4F3EF | 列表项标题优先，没有才用 detail `title` |
| 元数据行 | `caption` 次浅字 #D9C6B2，「2024 · 日本 · 动画 · 日语」：按 metadata 的 key 取 year / releaseDate / region / genre / language，有几个写几个，一个都没有就不出这行 | 不写 label，只写 value |
| 状态徽章 | `latestText` 做成胶囊，与库页集数徽章同一个；没有 `latestText` 而 metadata 有 status 时用 status | 底 #F2A65A 字 #141210，高 20 |
| 来源行 | `caption` #D9C6B2「来源名 · 主机名」 | 主机名取法与库页眉行相同 |
| 返回 | 左上 40pt 圆，白 18% 底 | 热区 44 |
| 收藏 | 右上 40pt 圆，心形与库页封面爱心同一对图，已收藏实心 #F2A65A；点了即收藏 / 取消，库页爱心跟着变 | 走 `ToggleFavoriteUseCase`，与库页同一条 |

头图区里的文字都是固定浅色（与类型横幅、深色瓷砖同一组取值），不随系统变。

## 六、线路与选集

**线路芯片**：两条以上线路才出。芯片文字 = 线路名（group `title` / `titleStrip` / App 切出来的「线路 N」）；样子与库页分类芯片同一个。默认选中含「上次看的那一集」的线路，没有历史选第一条；切线路只换网格。

**集号网格**：

| 项 | 取值 |
| --- | --- |
| 格子 | 自适应网格，最小宽 60、高 44、间距 10、圆角 12、卡片底；文字 `subheadline` semibold 主文字色，一行可缩到 0.8 |
| 集名 | 能从集名解出数字的（「第01集」「01」「EP 12」「第 3 话」）显示紧凑的「01」「12」；解不出的（「HD中字」「正片」「预告」）显示原文、格子按内容加宽；解析只影响显示，不改顺序 |
| 上次看的那一集 | 视频类型色描边 1.5pt + 类型色字，左上角一个小播放三角；历史一部作品只存最近一集，所以只标这一集 |
| 受限 / 付费 | `isRestricted == true` 右上小锁，`isPaid == true` 右上小币；nil 不标 |
| 点击 | 解析并播放这一集；被点的格子里转圈，解析期间互斥不变（`isLoadingPlayback`） |
| 单集 | 只有一集时网格只有一格，继续看按钮写「播放」；多条线路各一集（樱花的电影）是线路芯片 + 一格 |
| 顺序 | 分区标题右侧「24 集 · 正序」点了切「倒序」，只改显示顺序；当前线路不足 2 集不显示 |

规则没分组、首集标题不重复的扁平列表（樱花电影页），App 分不出哪些是同一集，照原样当四集显示；要分得清得 fwq 给这类站生成 group 规则，App 不猜。

## 七、继续看

- **数据**：进页时读本作品的历史（同来源、`detailURL` 相同；退到 `vodID`）。历史里的 `playPageURL` 与哪一集相同就是那一集；对不上用集名；都对不上（规则换过、站点改了地址）按钮仍写历史里的集名，点了用历史记录直接开播放器，与历史页点行同一条路。
- **文案**：见第四节第 2 行。
- **样子**：通栏胶囊，高 50，视频类型色底（浅色 #A85A12 白字 / 深色 #F2A65A 墨字，与选中芯片同一取值），左侧播放三角；解析中按钮内转圈、文字换「正在解析…」。
- **回来**：播放器关闭后重读历史，按钮文案、进度小字和网格高亮跟着换。

## 八、其余状态

| 场景 | 显示 |
| --- | --- |
| 正在取详情 | 头图区先用列表项的标题和封面画出来；继续看按钮位置一条骨架胶囊；简介位置两条骨架条；网格 10 个骨架格 |
| 取到了但没有选集 | 网格位置小空状态：`play.rectangle` 图标 +「没有剧集」+「这个来源没有给出任何剧集」+「下拉重试」；没有继续看按钮；头图、简介照常 |
| 详情取失败 | 同上，文案是错误原因，警示色三角；头图区仍用列表项数据；不再弹系统警告框 |
| 正在解析播放 | 被点的格子或继续看按钮内转圈；整页不再盖 72% 遮罩，其他格子照常可见 |
| 解析失败 | 网格上方一条警示色淡底横幅（与库页分类出错横幅同一个）写原因，点别的集或几秒后消失；不弹系统警告框 |
| 片源不可用 | 播放器自己的错误页，不在本页 |
| 下拉刷新 | 重取详情，历史一并重读 |
| 深色模式 | 头图区固定；卡片底、芯片、格子随系统；继续看按钮与选中芯片换深色取值 |

## 九、要追加的字段

**App / Core 侧自己补的**：

| 字段 | 在哪 | 为什么 |
| --- | --- | --- |
| `SourceDetailAttribute.key`（可空） | BrowseCraftCore：`DefaultVideoDetailRuleParser` 解析 `metadata[]` 时把规则里已有的 `id` 带出来；Runtime `VideoSourceDetailLoader` 转成运行期模型时一并带上 | App 才能把 year / region / genre / language 摆进元数据行、status 做徽章、director / cast 放简介下；没有 key 的条目照旧 label: value |
| 集名的数字解析 | App：`VideoDetailViewModel` 一个纯函数 | 只影响格子里显示什么，不改排序、不进存储 |
| 本作品的历史 | App：`LoadVideoWatchHistoryUseCase` 加按来源 + `detailURL` 取最近一条，经 `ReadingActivityPersistenceCoordinator` 给详情页 | 继续看按钮与高亮；现有表，不加列 |
| 收藏 | App：`VideoDetailViewModel` 注入 `ToggleFavoriteUseCase` | 右上爱心；与库页同一条 |

**向 fwq 提的**（定义点在 fwq，这里只写引用点）：`metadata[].id` 固定成 catalog 合同（受控词表、不得省略），多条线路各一集、规则没分组的站要生成 group / `titleStrip`。fwq 做完后由用户重生成樱花验收；App 侧的 `key` 透传不等 fwq。

**候选、本轮不做**：「看过的全部集」要新表（每集一行），还要进删除来源的连带清理和云同步的范围判断，单独立项。

## 十、视觉取值

不新增颜色，全部已在 `CatalogStyle.swift`：

| 项 | 取值 |
| --- | --- |
| 头图区 | 固定深色：没封面时底 #2B2117；标题 #F4F3EF，次文字 #D9C6B2；状态徽章底 #F2A65A 字 #141210；已收藏爱心 #F2A65A |
| 继续看按钮、选中线路芯片、上次看的集号 | 视频类型色：浅 #A85A12 / 深 #F2A65A（`CatalogKindStyle.of(.video).accent`）；底上的字浅色白、深色 #141210 |
| 页面底 / 卡片底（格子、未选芯片）/ 次级填充 | `pageBackground` / `cardBackground` / `fillBackground` |
| 解析失败横幅 | `warning` / `warningFill`，圆角 16 |
| 尺寸 | 头图区高安全区 + 236；海报 108×162 圆角 14；圆按钮 40（热区 44）；继续看 50 胶囊；芯片高 36；格子高 44、最小宽 60、圆角 12、间距 10；页边距 20 |
| 字号 | 标题 `title2` heavy；元数据、来源 `caption`；分区标题 `footnote` bold；格子 `subheadline` semibold；简介 `subheadline` |

## 十一、裁定

2026-10-08 用户裁定八项全取 A：模糊海报深色头图区 + 左侧小海报；集号网格；加继续看主按钮；解析时格内转圈、不盖遮罩；Core 加 `key` 透传；向 fwq 提两条需求；看过的全部集本轮不做；右上收藏按钮。

## 十二、不改的东西

- 选集的去重与切线路（`filteredEpisodeChapters`、`labelingRepeatedRoutes`）、`openEpisode` 的解析与播放器、历史的写入、规则与 Core 的解析语义（只加一个透传的 `key`）、三个入口。
- App 不提供规则创建或编辑入口（`BCA-UI-003`）；metadata 有什么由规则决定。

## 十三、实现位置

- `BrowseCraft/Features/Library/Video/Detail/VideoDetailView.swift`：整页重画——头图区、继续看、简介折叠、线路芯片、集号网格、骨架与空 / 失败态、解析失败横幅。
- `BrowseCraft/Features/Library/Video/Detail/VideoDetailViewModel.swift`：按线路分组、当前线路、排序、集名数字解析、本作品历史与继续看目标、收藏切换、metadata 按 key 摆位。
- `BrowseCraft/App/Composition/LibraryFeatureFactory.swift`：给详情 ViewModel 注入收藏用例。
- `BrowseCraft/Application/UseCases/History/ReadingHistoryUseCases.swift` 与 `ReadingActivityPersistenceCoordinator.swift`：按来源 + `detailURL` 取最近一条视频历史。
- BrowseCraftCore：`SourceDetailAttribute` 加 `key`，`DefaultVideoDetailRuleParser` 两处构造处传 `id`，测试补断言；BrowseCraftRuntime：`VideoSourceDetailLoader` 转换时带上 `key`。
- `BrowseCraft/Features/Library/Components/LibraryListTabBar.swift`：芯片抽成可复用的 `LibraryChipBar`，库页分类条与本页线路芯片共用。
- 三份 `Localizable.strings`：继续看四种文案、「选集」「简介」「展开」「收起」「正序 / 倒序」「N 集」「没有剧集」、解析失败横幅；删去「Description / Last / Loading Playback」。

## 十四、真机验收清单

- 模拟器没走到（需要多线路、多集的来源）：数字集号网格、线路芯片、正序 / 倒序、「下一集」/「再看一遍」、受限 / 付费角标、解析失败横幅、没有选集与取失败态。
- 顺带看两条 fwq 项：片源 403 的作品应提示换片源而不是整页兜底（`BC-EVIDENCE-082`）；选集无线路名的站应按重复集号分「线路 1 / 2」。
- 深色模式整页看一遍。
