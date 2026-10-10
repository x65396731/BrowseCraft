# 来源内搜索页的视觉与信息结构重设计

设计稿（画布，含樱花动漫视频结果、小說狂人书籍结果、めちゃコミック漫画结果、未搜索、搜索中、无结果、失败、登录、深色、尺寸与取值，共 10 张）：
[来源内搜索页重设计](https://claude.ai/artifact/1ddVwDYKrVWgumeTexrSZ8)；设计文档：[来源内搜索页重设计](https://claude.ai/artifact/BffzLQ9niatkct5WiRn8Hc)。
设计与实施状态见 [STATUS.md](../STATUS.md)。眉行、圆按钮、骨架、页内横幅的做法沿用三份库页合同与
[站点书详情页](Book-Detail-Page-Redesign-Design.md)；结果区原样复用三份库页合同的版式，本页不新增色值。

## 一、背景

来源内搜索页 `LibrarySearchView` 是库页重做之后唯一还留着系统外壳的入口页：系统导航栏「搜索 / 完成」、一个系统次级底色的圆角搜索框、一条分隔线、系统 `EmptyStateView`
（大放大镜、「搜索」、「输入关键词，在这个来源里搜索。」）；搜索中是居中转圈，无结果与失败也是同一个 `EmptyStateView` 换图标换文案。
它从三种库页的左上搜索圆按钮弹出，库页已经是自绘眉行 + 大标题 + 类型色芯片，三种详情页也都按统一语言重做过；从这些页面点进来落到一张白底系统表单，断得明显。

本页与其他页不同的几点，决定它不能照搬某一页的版式：

- **三种类型共用一页**。搜索结果已经经 `LibraryContentView` 按来源 kind 分流复用库页三套版式（两列海报墙、三列封面墙、书脊行），本页的结果区不另起版式，只做外壳、输入与状态。
- **它是 sheet，不是推入页**。库页用 `.sheet` 弹出，里面自带 `NavigationStack`，结果点开的详情页在 sheet 内部推入；收起靠右上按钮或下拉。详情页「隐藏底栏只留返回」的约定在 sheet 里不适用。
- **键盘一直在**。进页自动聚焦，页面大半时间下半截被键盘盖住，未搜索态与无结果态都要在键盘之上的半屏里站住。
- **能力由规则声明**。只有规则带 `searchRules` 的来源才有搜索按钮；分页也由搜索规则的 `pagination` 声明，当前线上规则都不带分页，结果区只有一页。

## 二、规则与本机实际给什么数据

搜索这条链三层都已经接好，页面只是壳。Core 三条 kind 各有一个搜索规则模型（`SearchRule` / `VideoSearchRule` / `BookSearchRule` / `ComicSearchRuleV2`），字段都是 fwq `BC-SEARCH-007`
的那九个：`id`、`url`（恰一个 `{keyword}` 槽位）、`method`、`keywordEncoding`、`request`、`listRuleRef` 或自带 `item + fields`、`pagination`。Runtime 三条 kind 都实现 `SourceSearchRuntime.search`，
输出与列表同型的 `SourceListOutput`（`items` + `pagination`）；App 的 `SearchSourceContentUseCase` 只问能力、传关键词与页码，`LibraryViewModel` 把结果经同一个 `SourceListContentItemMapper` 映成 `ContentItem`。

本机五个模拟器库里一共 14 条真实搜索规则（视频 7、漫画 3、书 4），逐条核对的结果：

| 元素 | 规则 / Runtime 给什么 | 14 条真实规则的现状 | 页面怎么用 |
| --- | --- | --- | --- |
| 有没有搜索 | `runtime.capabilities.supportsSearch`：规则有一条可解析的 `searchRules[]` 才为真 | 樱花动漫、低端影视、gimytv、xiaoheimi、动漫MIKU、91porn 有；威视、看片狂人、jable、nunuju 没有。めちゃコミック、ho5ho、MYCOMIC 有；再漫画、LINE WEBTOON 带空数组，CCC、Komiic、快看、动漫嗨没有。小說狂人、quanben、思兔、笔趣阁有；飘天、半夏、茶香、Loyal Books、sfacg 没有 | 决定库页出不出搜索按钮；本页进来时一定为真 |
| 请求形状 | `url` 模板 + `method` + `keywordEncoding` | 14 条全部 GET、全部 `percentEncoded`、恰一个 `{keyword}`；一个来源恰一条 | 页面不碰；关键词去首尾空白后交给用例 |
| 结果条目 | `SourceContentItem`：`title`、`detailURL`、`coverURL`、`latestText`、`itemReference` | 字段与该来源的列表完全一致（7 条走 `listRuleRef` 直接借列表选择器，7 条自带 `fields` 但键集与列表相同）。视频站多半没有封面以外的东西；书站有 `latestText` | 结果卡片 = 库页同一张卡片，按 kind 分流 |
| 分页 | `pagination`；Runtime 漫画与书会解析下一页，视频 `executeSearch` 不接 `page` | 14 条全部没有 `pagination`（fwq `BC-SEARCH-006`：只在结果页有可执行分页证据时写） | App 侧接 `nextPage` / `loadNextSearchPage`，规则声明分页时才出分页脚 |
| 空结果 | 合法结果，不报错（视频 loader 明写「结果为空是合法的搜索结果」） | — | 无结果态 |
| 失败 | `RuleExecutionErrorClassifier.userMessage(for:)` 一句话 | 网络、解析、渲染守卫、登录墙都走这一句 | 失败态 + 重试 |
| 收藏 / 历史 | 结果条目与列表条目同 id，`favoriteItemIDs` 同一集合 | — | 卡片爱心与库页同步 |
| 结果数 | `items.count` | 小說狂人一次返回整页（几十条）、视频站 10–30 条 | 眉行写「N 个结果」 |

**没有的东西**（合同里没有槽位，页面不画）：搜索建议 / 联想词、分类内搜索、排序、结果总数（只有本页条数）、站点的「热搜」。**本机也没有的**：搜索历史，App 没有任何关键词存储，裁定不做。

**关键词的限制**只有一条：去首尾空白后非空。规则不声明长度与字符集，站点拒绝时按失败态显示。

## 三、入口、相邻页面与范围

- **入口**：只有一个，库页大标题右侧的 40pt 搜索圆按钮（视频 / 漫画 / 书籍库同一个），`LibraryView` 用 `.sheet` 弹出本页；按钮只在 `selectedSourceSupportsSearch` 为真时出现。进页自动聚焦输入框、弹键盘。
- **出口**：结果卡片在 sheet 自己的 `NavigationStack` 里推入——视频进影视详情（`LibraryContentView` 内部的 `NavigationLink`），漫画进漫画详情或单章来源直接进阅读器，书进站点书详情；三条链与库页一样
  （`navigationDestination(item:)` 的写法不动）。关闭靠右上按钮或下拉 sheet，回库页。
- **相邻**：下面是重做过的库页（页面底色、眉行 + 大标题、类型色芯片），上面推入的是三种详情页。本页跟随系统深浅，底色用页面底，类型色只做点缀（眉行图标、聚焦描边）。
- **范围**：顶行、搜索框、结果区眉行、四种状态（未搜索 / 搜索中 / 无结果 / 失败）、键盘与滚动的关系、关闭后的状态保留；外加结果分页的 App 侧接线和登录墙的「登录」入口。
- **不在范围**：结果卡片本身（由三份库页合同定）；三种详情页；规则侧的搜索发现与分页证据（fwq）；视频 Runtime `executeSearch` 不接 `page` 的补齐（规则没分页时无感，记一笔不在本页做）；跨来源搜索。

## 四、页面结构

sheet 跟随系统深浅，底色取页面底，隐藏系统导航栏；顶行与搜索框固定在上方，下面是一个滚动的结果区。从上到下：

| 顺序 | 块 | 内容 | 什么时候出现 |
| --- | --- | --- | --- |
| 1 | 顶行 | 左：眉行「▶ 视频 · 樱花动漫」（类型图标取类型色，其余 `caption` 次级色）+ 标题「搜索」`title2` bold；右：40pt 卡片底圆按钮（叉）关闭 sheet | 一直 |
| 2 | 搜索框 | 高 48、卡片底、圆角 16；左放大镜次级色；占位「搜索 樱花动漫」；有字时右侧清空叉；聚焦时 1.5pt 类型色描边；键盘回车键 = 搜索 | 一直；进页自动聚焦 |
| 3 | 结果眉行 | 「“关键词” · 12 个结果」`caption` 次级色；搜索中写「正在搜索 “关键词”」 | 搜索中和有结果时 |
| 4 | 结果 | `LibraryContentView` 原样：视频两列海报墙 / 漫画三列封面墙 / 书脊行，爱心、长按菜单、往详情的链路都是库页的；规则声明分页时底部挂库页同一个分页脚 | 有结果时 |
| 5 | 未搜索 | 插画 `EmptyStateSearch`（高 150）+「搜索 樱花动漫」`headline` +「输入关键词，按键盘上的搜索。结果来自这个来源自己的搜索。」`subheadline` 次级色；顶对齐（搜索框下 24pt） | 还没搜过，或清空后 |
| 6 | 搜索中 | 按 kind 的骨架 `LibrarySkeletonGridView`（posterWall / comicWall / bookList），上方是眉行 | 请求进行中 |
| 7 | 无结果 | 同一张插画 +「没有找到 “关键词”」+「换个关键词试试。」，顶对齐 | 搜完是空 |
| 8 | 失败 | 警示淡底横幅（图标 + 原因 + 右侧「重试」；登录墙且来源有登录页时多一个「登录」），在搜索框下 16pt | 请求抛错 |

页边距左右 20pt。同一时刻结果区只出 4 – 8 里的一种。没有分类芯片、没有「上次看到」瓷砖、没有下拉刷新（重搜就是重试）。

## 五、顶行与搜索框

| 位置 | 内容 | 取值 |
| --- | --- | --- |
| 眉行 | 类型图标（视频播放三角 / 漫画气泡 / 书本；整站有声写「有声书」配耳机）+「视频 · 樱花动漫」；来源名取 `source.name`，超长尾省略 | `caption` 次级色，图标类型色；与库页眉行同一个写法，但写来源名不写主机名（库页大标题已经是来源名，这里没有大标题位给它） |
| 标题 | 「搜索」 | `title2` bold 主文字色；不用 `largeTitle`，sheet 里键盘占半屏，头部要矮 |
| 关闭 | 40pt 卡片底圆按钮，图标 `xmark` `headline` semibold；热区 44 | 与库页 / 详情页的圆按钮同一个；点了 `dismissSearch()` |
| 搜索框 | 高 48，卡片底，圆角 16（连续曲线）；左 12pt 处放大镜 `body` 次级色；输入 `body` 主文字色；占位「搜索 樱花动漫」次级色 | 聚焦时外描 1.5pt 类型色（`CatalogKindStyle.accent`），失焦时无描边；不自动大写、不自动更正 |
| 清空 | 有字时右侧 `xmark.circle.fill` 次级色，热区 44 | 点了清空输入、回未搜索态、重新聚焦 |
| 提交 | 键盘回车键标「搜索」（`submitLabel(.search)`）；输入中不自动搜 | 提交后收键盘、记下本次关键词给眉行；空白关键词不发请求 |
| 间距 | 安全区顶 12 → 眉行 → 4 → 标题行 → 14 → 搜索框 → 16 → 结果区 | 顶行 + 搜索框合计约 128pt |

搜索框与结果区之间不画分隔线。搜索框不贴顶滚动，它本来就在滚动区之外。

## 六、结果区

| 位置 | 内容 | 取值 |
| --- | --- | --- |
| 眉行 | 「“关键词” · 12 个结果」；关键词是提交时记下的那个，不随输入框改字变 | `caption` 次级色，左对齐 20pt，下距网格 10pt；数字 `monospacedDigit` |
| 网格 / 行 | `LibraryContentView(items: searchResults, …)` 原样：视频两列海报（集数徽章、爱心）、漫画三列封面（最新话）、书脊行（最新 · 原文） | 三份库页合同的取值，本页不重复也不覆盖 |
| 点卡片 | 与库页同一条链推入详情；详情页在 sheet 内，返回回到结果，结果与滚动位置保留 | `navigationDestination(item:)` 不动 |
| 爱心 / 长按 | 卡片自带；收藏后库页同一条目的爱心同步（同一个 `favoriteItemIDs`） | — |
| 分页脚 | 规则声明 `pagination` 且 Runtime 报出下一页时，网格底部挂库页同一个触底哨兵与分页脚 | 当前 14 条规则都没有，所以现在看不见；接线要做，不留死路 |
| 键盘 | 提交时收键盘；结果区 `scrollDismissesKeyboard(.interactively)`，点搜索框重新弹 | 没有结果区点空白收键盘的手势（会和卡片点击打架） |
| 底部 | 内容底距安全区 24pt | sheet 里没有底栏 |

结果区的宽、列距、卡片尺寸都由 `LibraryContentView` 自己定；本页只给它一个滚动容器和上方的眉行。搜索结果不写历史，点开的作品和从库页点开一样进历史。

## 七、其余状态

| 场景 | 显示 |
| --- | --- |
| 未搜索 | 插画 `EmptyStateSearch`（看板娘双手举着一面空镜片的大放大镜；已登记资产 274×540，库页视频库改用自己的图后当前没有页面在用它）按高 150 画，下面「搜索 樱花动漫」`headline` 与一句说明；整块顶对齐，搜索框下 24pt，键盘弹起的半屏里插画与两行字都看得全 |
| 搜索中 | 眉行「正在搜索 “关键词”」+ 按 kind 的骨架网格；搜索框照常可编辑，再次回车取消上一次、发新请求（`performSearch` 走可取消的 Task） |
| 无结果 | 同一张插画 +「没有找到 “关键词”」+「换个关键词试试。」，顶对齐；搜索框里的字保留、不自动聚焦 |
| 失败 | 警示淡底横幅（`warningFill` 底、圆角 16，左三角感叹号 `warning`，中间 `RuleExecutionErrorClassifier.userMessage` 的一句话 `caption` 次级色，右侧「重试」胶囊）；与漫画 / 书详情的页内横幅同一套；重试 = 用上次关键词重搜 |
| 需要登录 | 错误归类为 `accessRequired` / `protectedResource` 且 `selectedSourceLoginState != nil` 时，横幅右侧多一个「登录」；点了在 sheet 内 `fullScreenCover` 开 `SourceLoginView`（与书详情同一写法），登录成功后自动用上次关键词重搜 |
| 结果里有封面取不到 | 卡片自己的占位，与库页同 |
| 结果里的只读信息 | 与库页同一张卡片、同一行给同一信息：漫画封面上的「读到 4-2」角标、整站有声来源的耳机与「听」措辞；长按「继续读」不接（搜索页不接阅读器） |
| 关闭再打开 | 关键词与结果保留（状态本来就在 `LibraryViewModel` 上），滚动位置回到顶部（sheet 关闭即销毁视图，不为此另存滚动位置）；重新打开时有结果就不自动聚焦、不弹键盘，没有结果才聚焦；上次失败留着横幅时也不聚焦（键盘会盖住横幅上的「重试」「登录」） |
| 换来源 | 库页切换来源时清空关键词与结果（原来不清，上个来源的结果会留到下个来源的搜索页里） |
| 深色 | 跟随系统；页面底 / 卡片底 / 类型色都是动态色，插画透底 |
| 无障碍 | 关闭按钮标「关闭搜索」；眉行与结果数合并成一个元素读出；插画对读屏隐藏（`EmptyStateIconView` 已如此） |

未搜索与无结果都不用库页的 `LibraryPlaceholderView`：那个组件自带「下拉可重新载入」的示意，本页没有下拉刷新。

## 八、要追加的字段与接线

合同不动，规则不加字段；所有改动在 App 层。

| 层 | 要补什么 | 为什么 |
| --- | --- | --- |
| `LibraryViewModel` | `submittedSearchKeyword`（提交时定格的关键词） | 眉行、无结果、重试都用它，不跟输入框走 |
| `LibraryViewModel` | `searchNextPage: Int?` + `loadNextSearchPage()`；`performSearch` 记下 `output.pagination?.nextPage` | 分页脚接线；用例 `execute(source:keyword:page:)` 已有 `page` 参数 |
| `LibraryViewModel` | `searchTask` 可取消；`clearSearch()`；切换来源时调 `clearSearch()` | 连续回车不叠请求；清空叉与换来源 |
| `LibraryViewModel` | `searchFailureNeedsLogin: Bool`（按 `RuleExecutionErrorClassifier` 的归类） | 横幅要不要出「登录」 |
| `LibrarySearchView` | 自绘顶行、搜索框、眉行、四种状态；`fullScreenCover` 挂 `SourceLoginView`；`scrollDismissesKeyboard` | 本页主体 |
| `LibraryContentView` | 不改；`nextPage` / `loadNextPage` 从 ViewModel 的搜索字段传 | 分页脚复用 |
| 字符串 | 三份 `Localizable.strings` 新增：「搜索 %@」占位与标题、「输入关键词，按键盘上的搜索。结果来自这个来源自己的搜索。」、「正在搜索 “%@”」、「“%@” · %ld 个结果」、「没有找到 “%@”」、「关闭搜索」、「清空」；「换个关键词试试。」「重试」「登录」沿用现有 | — |
| 资产 | `EmptyStateSearch` 已在 `bundled-image-asset-budgets.txt` 登记，不新增 | — |

**不在本页做、但记一笔**：视频 Runtime `VideoSourceListLoader.executeSearch` 不读 `input.page`、也不解析搜索结果页的分页；漫画与书都会。等哪天 fwq 给视频搜索规则写了 `pagination`，Runtime 那一层要补；到那时本页什么都不用改。

## 九、视觉取值

本页不新增任何色值；全部取自 `CatalogStyle.swift`。

| 用处 | 取值 | 来源 |
| --- | --- | --- |
| 页面底 / 卡片底 | `CatalogPalette.pageBackground` / `cardBackground` | 搜索框、关闭圆按钮用卡片底 |
| 类型色 | `CatalogKindStyle.of(source).accent`（视频琥珀 / 漫画淡紫 / 书籍青绿） | 眉行图标、搜索框聚焦描边 |
| 警示 | `warning` / `warningFill` | 失败 / 登录横幅 |
| 文字 | 主文字 / 次级色（系统） | — |
| 圆角 | 搜索框 16、横幅 16、圆按钮正圆、重试 / 登录胶囊 | 与库页、详情页同 |
| 字号 | 眉行 `caption`；标题 `title2` bold；输入 `body`；结果眉行 `caption`；空态标题 `headline`、说明 `subheadline`；横幅文字 `caption` | 系统字体 |
| 尺寸 | 搜索框高 48；圆按钮 40（热区 44）；插画高 150；页边距 20；搜索框与结果区间距 16 | — |
| 插画 | `EmptyStateSearch`（274×540，按高 150 画） | 未搜索与无结果共用 |

## 十、裁定

2026-10-09 用户裁定十四项全取 A：自绘眉行 + 「搜索」+ 圆形关闭；卡片底搜索框 + 聚焦类型色描边；只靠键盘搜索键提交；未搜索态插画顶对齐；不做最近搜索；搜索中按 kind 骨架；
无结果同一张插画；失败横幅 + 重试（登录墙多「登录」、登录后自动重搜）；结果眉行「“关键词” · N 个结果」；App 侧接分页；关闭再打开保留状态、换来源清空；提交收键盘、滚动交互式收键盘；
类型色只用在眉行图标与聚焦描边；跟随系统深浅。

## 十一、不改的东西

- `SearchSourceContentUseCase`、Core 与 Runtime 的搜索链；规则的搜索发现与分页证据（fwq）。
- `LibraryContentView` 与三种卡片；三种详情页；库页的入口按钮与 `.sheet`。
- App 不提供规则创建或编辑入口（`BCA-UI-003`）；有没有搜索由规则决定。

## 十二、实现位置

- `BrowseCraft/Features/Library/Components/LibrarySearchView.swift`：去掉系统导航栏标题与「完成」，自绘顶行、搜索框、结果眉行、四种状态、横幅、登录 `fullScreenCover`、分页接线、键盘行为；
  `NavigationStack` 与两个 `navigationDestination(item:)` 原样保留。
- `BrowseCraft/Features/Library/LibraryViewModel.swift`：第八节的字段与方法；切换来源处调 `clearSearch()`；登录成功后若搜索页正开着且失败是登录墙，自动重搜。
- 三份 `Localizable.strings`（zh-Hans / zh-Hant / en）：第八节的词条。
- 不改：`LibraryView.swift`（入口按钮与 sheet 不动）、`LibraryContentView.swift`、`SearchSourceContentUseCase.swift`、Core / Runtime。
- 资产：不新增。

## 十三、真机验收清单

- 模拟器没走到：搜索中骨架（请求太快抓不到）、无结果（czbooks 对任意关键词都回 40 条）、失败 / 登录横幅、分页脚（线上搜索规则都不带分页）、视频与漫画来源的结果版式。
- 深色模式整页看一遍。
