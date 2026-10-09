# 站点书详情页的视觉与信息结构重设计

设计稿（画布，含小說狂人主稿、没读过、Loyal Books 有声书、深色、加载、失败、登录、没有章节、尺寸与取值，共 9 张）：
[站点书详情页重设计](https://claude.ai/artifact/LGf2oMCv9GYDv7v78bRNKN)；设计文档：[站点书详情页重设计](https://claude.ai/artifact/KRF8Q269kKNwdt2pUp4P4u)。
设计与实施状态见 [STATUS.md](../STATUS.md)。固定顶按钮、贴顶分区头、分段芯片、页内横幅与骨架的做法沿用
[漫画详情与章节页](Comic-Detail-Page-Redesign-Design.md)，颜色、圆角、字号沿用 [库页书籍库](Library-Book-Page-Redesign-Design.md)，本页不新增色值。

## 一、背景

站点书详情页 `BookSiteDetailView` 是三种类型的详情页里最后一个还是系统 `List` 的：一张卡片（封面 72×100、书名、来源、「N chapters」）、
一个「开始 / 继续阅读」行、「Chapters」逐行列到底，续读章右侧一个蓝色书签；字面还有英文留痕。库页书籍库改成书脊行之后，点进来落到这张白底表单，断得最明显。

书的详情页和影视、漫画的不同：

- 没有海报可以撞。影视海报模糊压暗做头图、漫画封面配淡底；文字书站多半没有封面，头部只能靠文字和结构站住。
- 目录是上千章的。网文一本 1,297 章、章名有话名，只能是行列表，而且「跳到第 800 章附近」是刚需。
- 进度不是「第几页」。书记的是 Readium Locator：章内位置 + 全书 `totalProgression`，有声书还是时间点。
- 读书 kind 包含有声书。同一张页要在有声作品上写「开始 / 继续收听」、章节跳进播放器；是不是有声要等章节装配完才知道。

所以书的详情页用以文字为主的书页：页面底色上一张小封面（带书脊线）配书名、来源与分类、章数；一张贯通的继续卡片写章节与全书进度（有声「继续收听」）；
贴顶分区头（章数 / 正序倒序 / 分段芯片）下是行列表的目录，已读变淡、上次读到标竖条。影视深色头图、漫画淡底头部、书页面底色 + 文字——三种详情页三种质感。

## 二、规则与本机实际给什么数据

详情这条链有三层：Core `DefaultBookRuleParser.parseDetail` 只读五个键（`title` 必有，`cover / author / description / language` 可选）；Runtime 只填这五项；
App 的 `BookPublicationAssembler` 再把 `description` 丢掉。三十四份真实规则的 detail `fields` 只有 `title`，笔趣阁、嗶哩輕小說、Royal Road、Loyal Books 多一个 `cover`，没有一份声明作者或简介。

| 元素 | 来源 | 现状 | 页面怎么用 |
| --- | --- | --- | --- |
| 书名 | manifest `title`，经 `SiteBookTitle.preferred` 与列表标题取较短的 | 都有 | 大标题 |
| 封面 | manifest `coverURL` → 列表 `cover` → `BookCoverPlaceholder` | 多数文字站没有 | 小封面 72×96 带书脊线 |
| 作者 | manifest `author` | 规则都不给 | 有才出，行位不留 |
| 简介 | Runtime `description` 已填，装配器透传后 | 规则都不给 | 有才出 |
| 来源 · 分类 | `source.name` + 列表所属分类 | 都有 | 头部小字 |
| 章数 | `manifest.items.count` | 都有 | 头部「N 章」与分区头 |
| 状态 / 更新时间 / 标签 | 合同没有槽位 | 没有 | 不显示 |

**章节**（`BookPublicationItem`）只有 `title`、`chapterURL`、`kind`（text / audio）；`order` 与 `group` 规则不生成；`order` 在 Runtime `BookSourceRuntime.loadDetail` 构造 `SourceChapter` 时丢弃，`group` 由 Runtime 映成 `SourceChapter.subtitle`、到 `BookPublicationAssembler` 才丢；没有时长、付费、限制标记。目录顺序就是规则抓到的顺序
（笔趣阁页顶「最新章节」块排在前面、小說狂人夹着公告行，都是规则与 Runtime 的事，页面照列）。

**章节标题的形状**：小说站几乎全是「编号 + 章名」，纯编号目录几乎没有（小說狂人 683 条解出 679、novels 1531 全解出、Royal Road 106/109）；解不出的是公告、Epilogue、「作品相關」。
`ComicChapterTitleParser` 原来一条中文数字都解不出（笔趣阁「第八百六十二章」整本失败），本轮扩展它认中文数字。

**是不是有声书**：`manifest.isAudiobook` = 章节里有 `.audio` 项，按章节地址扩展名判，要等章节装配完才知道；库页那轮的「整站有声」（reader 规则全 audio）进页就能算，加载中的措辞先用它。
站点有声书没有时长，Readium 算不出全书 `totalProgression`，只有章内进度和 Locator 里的 `t=秒`。

**进度与历史**：`BookReadingProgress.locatorJSON` 是 Readium Locator，文字书 `totalProgression` = 章序 / 章数。原先详情页用 Locator 的 `href`（`chapters/000N.xhtml`，按下标编）反查续读章，
目录一变就对到别的章；`BookReadingHistory`（一书一条）里的 `chapterURL` 是稳定键。书没有按章的已读记录；书签只接在阅读器。

**收藏**：`FavoriteContentKind.book` 存在，库页与收藏页都能收藏书；详情页原先没有注入收藏用例。

## 三、入口、相邻页面与范围

- **入口**：库页书脊行、搜索结果、收藏页行、库页瓷砖长按「打开作品」都推入本页；进入后隐藏底栏，左上返回。头部在详情取回来之前先用列表的书名与封面画。
- **出口**：继续卡片 / 开始按钮与章节行都推入 `BookReaderView`（本视图自己的 `navigationDestination(item:)`，不能换成 `NavigationLink(value:)`，混用栈序会错）；
  继续卡片不带章节（按续读 Locator 接着），点章节带章节；文字书进 EPUB 阅读器、有声书进播放器，分流在阅读器里按 manifest 做。右上收藏切换收藏。
- **相邻**：上一页是库页书籍库（页面底色、书脊行、绿色类型色），下一页是白底纸页样的阅读器。本页用页面底色 + 卡片底，绿色只用在继续卡片小字、进度条、上次读到的竖条、选中芯片和已收藏爱心。
- **范围**：本页全部——头部、继续卡片 / 开始按钮、简介（有才出）、贴顶分区头与分段芯片、章节目录、加载 / 失败 / 登录 / 没有章节；外加详情页接读书历史做续读章的稳定键、注入收藏用例、
  装配器透传简介、解析器认中文数字、Locator 的 `t=` 与 `progression`。文字书与有声书同一版式，有声只换措辞与图标。
- **不在范围**：EPUB 阅读器与有声书播放器的样式、书签 sheet；Runtime 不支持的目录分页与 `chapterAPI`；规则侧的抓取问题（向 fwq 提）；库页与历史页。

## 四、页面结构

页面跟随系统深浅，底色取页面底，隐藏系统导航栏与底栏；返回与收藏两个 40pt 圆按钮固定在安全区顶（与漫画详情同）。从上到下：

| 顺序 | 块 | 内容 | 什么时候出现 |
| --- | --- | --- | --- |
| 1 | 头部 | 页面底色上：左封面 72×96 带书脊线；右侧书名 `title2` bold 最多三行、作者行（有才出）、「来源 · 分类」小字、「1,297 章」（有声「耳机 有声书 · 17 章」类型色） | 一直；进页先用列表的书名与封面画，详情回来再补章数 |
| 2 | 继续卡片 / 开始按钮 | 有续读位置：高 88 的卡片「继续阅读 · 章名 · 全书 N% · 时刻」+ 3pt 进度条；没有：通栏胶囊「从第 1 章开始读」（有声「继续收听」/「从第 1 章开始听」） | 章节取回来之后；取回前画骨架条 |
| 3 | 简介 | 三行折叠，点展开 | 有 `description` 时 |
| 4 | 贴顶分区头 | 「章节 · 1,297 章」+ 右侧「正序 / 倒序」；≥ 60 章时下面一排分段芯片，点了滚到段首（`LibraryChipBar`） | 有章节时；滚动时停在固定按钮下 |
| 5 | 章节目录 | 行列表：编号柱 + 章名，解不出编号的行整行写标题；上次读到的行左缘类型色竖条，它之前的行变淡 | 有章节时 |
| — | 加载 / 失败 / 登录 / 没有章节 | 见第七节 | 对应状态时 |

页边距左右 20pt。与影视、漫画详情的区别：没有头图也没有淡底；继续卡片写章节与全书百分比而不是集数或页数；目录只有行列表一种形态。

## 五、头部与继续卡片

| 位置 | 内容 | 取值 |
| --- | --- | --- |
| 封面 | 72×96（3:4），manifest 封面 → 列表封面 → `BookCoverPlaceholder`；请求配置取规则的图片请求配置 | 圆角 8，左缘 2pt 书脊线黑 18% |
| 书名 | `SiteBookTitle.preferred`，`title2` bold 最多三行 | 主文字色 |
| 作者 | manifest `author`，`subheadline` 次级色 | 有才出 |
| 来源 · 分类 | `source.name` + 当前分类名，`caption` 次级色 | 一直 |
| 章数 | 「1,297 章」`caption` 次级色；有声书「耳机 有声书 · 17 章」类型色 | 章节取回来后；取回前骨架条 |
| 右上 · 收藏 | `TabFavorites` / `TabFavoritesOutline` 18pt 在 40pt 卡片色圆里，已收藏实心类型色 | 点了即收藏 / 取消 |

**继续卡片**（有续读位置时）：卡片底、圆角 16、高 88，左缘 4pt 类型色竖条；小封面 48×64（有声书上压耳机小圆）；三行：「继续阅读」/「继续收听」`caption` 类型色 → 章名 `headline` 一行 →
文字书「全书 12% · 昨天 21:40」/ 有声书「12:34 · 昨天 21:40」`caption` 次级色；底边 3pt 进度条写 `totalProgression`（有声书没有就不画）；行尾 36pt 类型色圆底图标。点 = 不带章节开阅读器。

- 章名与时刻从读书历史来（`chapterTitle`、`visitedAt`），历史没有时退回 Locator `href` 对法。
- 「全书 12%」就是 `totalProgression`，小于 1% 写「刚开始」。
- 有声书的「12:34」解 `locatorJSON` 里 `locations.fragments` 的 `t=秒`。

**开始按钮**（没有续读位置时）：通栏 50 胶囊，类型色底：「从第 1 章开始读」/「从第 1 章开始听」；起始章解不出编号「开始读 · 章名」，只有一章「开始阅读」。起始章 = 显示顺序的第一章。

加载中按钮的措辞用「整站有声」先定，章节回来后按 `manifest.isAudiobook` 纠正。

## 六、章节目录

只有行列表一种形态。卡片底、圆角 16、行间 0.5pt 分隔线、一行最小高 48。

| 位置 | 内容 | 取值 |
| --- | --- | --- |
| 编号柱 | `ComicChapterTitleParser` 解出的编号，宽 48，`subheadline` monospacedDigit 次级色 | 解不出时不出编号柱，整行从左缘写标题 |
| 章名 | 解出编号时写话名，话名为空写「第 N 章」；解不出写原标题；`body` 主文字色最多两行 | — |
| 上次读到 | 左缘 3pt 类型色竖条、章名类型色 semibold、行尾「读到 12%」（Locator `progression`；有声「12:34」） | 按读书历史 `chapterURL` 对，退回 Locator `href` |
| 已读 | 显示顺序里排在上次读到之前的行文字变淡（书没有按章的已读记录，这是推定） | 倒序时同样按正序位置算 |
| 点行 | 带章节推入阅读器 / 播放器 | 按下行底 `fillBackground` |

- 贴顶分区头：「章节 · 1,297 章」+「正序 / 倒序」；切换只翻显示顺序，不进存储；默认照规则抓到的顺序。
- 分段芯片：≥ 60 章时每 50 章一段，芯片写段首–段尾编号（解得出时）或序号；点了滚到段首，不是筛选；逻辑复用 `ComicChapterSegment`。段首要落在贴顶分区头下面：`scrollTo` 的锚点按分区头高度 / 滚动区可见高度换算，不用 `.top`（`.top` 会让段首两行压在分区头底下）。
- 解析结果、显示顺序、分段在章节变化或翻转时算一次，千章目录不在每次渲染时重算。

## 七、其余状态

| 场景 | 显示 |
| --- | --- |
| 进页加载中 | 头部先用列表的书名与封面画好，章数行、继续卡片位、分区头与 8 行目录都是骨架 |
| 从阅读器 / 播放器回来 | 不重取详情，只重读续读位置与读书历史 |
| 取详情失败 | 头部照留；继续卡片位换成警示色淡底横幅：图标 + 错误原因 + 右侧「重试」；目录不出 |
| 来源需要登录 | 来源有登录页时横幅右侧多一个「登录」（打开来源登录页，与漫画详情同一套横幅） |
| 有详情但没有章节 | 分区头「章节 · 0 章」下一张卡片「这本书还没有章节」；没有开始按钮 |
| 公告行 | 照列、没有编号柱，点了照样进阅读器 |
| 深色模式 | 页面底、卡片底、分隔线随系统；类型色切到 #5CC8B0；没有固定深色块 |
| 下拉 | 不加下拉刷新（详情与阅读器共用 5 分钟缓存，失败有「重试」） |

## 八、要追加的字段与查询

不加表、不加列、不动规则；都是 App 侧接线，每条都是通用机制。

| 项 | 在哪 | 为什么 |
| --- | --- | --- |
| 详情页读读书历史 | `BookSiteDetailViewModel` 注入 `BookReadingHistoryRepository`（按 `bookItemID` 取一条） | 续读章的稳定键；继续卡片的章名与时刻 |
| 收藏 | `BookFeatureFactory.makeSiteDetailViewModel` 注入 `ToggleFavoriteUseCase` | 右上收藏按钮 |
| 简介透传 | `BookPublicationManifest` 加 `description`，装配器从 `metadata.description` 透传 | 规则声明了就能显示 |
| 章名解析认中文数字 | `ComicChapterTitleParser` 加中文数字分支 | 笔趣阁、SF 桌面版整本解不出编号；漫画一起受益 |
| 有声书时间点、章内进度 | 解 `locatorJSON` 的 `locations.fragments` `t=` 与 `locations.progression` | 继续卡片第三行、上次读到行尾 |
| 整站有声 | 复用 `ResolveLibrarySourcePresentationUseCase.isAudiobookSource` | 加载中按钮措辞 |
| 登录入口 | `BookFeatureFactory` 注入凭据存储，详情页用 `LibrarySourceLoginStateResolver` 得登录态 | 失败横幅的「登录」 |

**向 fwq 提的**（合同已允许、生成器没覆盖，不改合同）：① 详情声明 `author` 与 `description`；② 章节 `order`；③ Royal Road 章节规则可能把日期锚点的「ago」当成章名（本地规则推断，要在线上复核）；
④ 笔趣阁目录分 9 页且页顶「最新章节」块排在前面；⑤ 书的 `latestText` 统一为裸章节名（库页那轮）。五条写成一份需求文本。

**候选、本轮不做**：详情页列书签；Runtime 支持目录分页与 `chapterAPI`；有声书时长。

## 九、视觉取值

| 项 | 取值 |
| --- | --- |
| 书籍类型色（随系统） | 浅 #1E7D68 / 深 #5CC8B0：继续卡片小字与竖条、进度条、开始按钮底、上次读到的竖条与章名、选中分段芯片、已收藏爱心、有声书小图标 |
| 页面底 / 卡片底 / 按下底 | `pageBackground` / `cardBackground` / `fillBackground` |
| 分隔线 | 系统 `separator` |
| 警示 | `warning` / `warningFill`：失败 / 登录横幅 |
| 圆角 | 封面 8、继续卡片 16、目录卡片 16、横幅 16、芯片与开始按钮胶囊 |
| 尺寸 | 页边距 20；固定按钮圆 40；头部封面 72×96、与文字间距 14；继续卡片高 88、封面 48×64、竖条 4、进度条 3；开始按钮高 50；分区头高 44；芯片高 36（`LibraryChipBar`）；目录行最小高 48、编号柱宽 48、上次读到竖条 3 |
| 字号 | 书名 `title2` bold；作者 `subheadline`；来源与章数 `caption`；继续卡片小字 `caption`、章名 `headline`；分区头 `headline`；编号柱 `subheadline` monospacedDigit；章名 `body`；简介 `subheadline` |

## 十、裁定

2026-10-09 用户裁定十三项全取 A：页面底色头部；继续卡片（章名 + 全书 % + 进度条 + 时刻）；续读章先按读书历史对；右上收藏；编号柱行列表；解析器扩中文数字；上次读到之前的行变淡；
≥ 60 章分段芯片；有声书继续卡片解 `t=` 写时间点；上次读到行尾写章内进度；装配器透传简介；页内横幅 + 重试 / 登录；向 fwq 提五条合成一份需求文本。
并确认 fwq 侧不需要新增字段，只需覆盖合同已允许的字段与修两处抓取。

## 十一、不改的东西

- 详情与章节的取法、5 分钟 `BookPublicationCache`、阅读器与播放器、书签、进度写入；章节推入阅读器的方式。
- 库页、历史页、收藏页；规则与 Runtime 的目录顺序、分页。
- App 不提供规则创建或编辑入口（`BCA-UI-003`）；作者、简介等字段有无由规则决定。

## 十二、实现位置

- `BrowseCraft/Features/Library/Book/Site/BookSiteDetailView.swift`：系统 `List` 换成 `ScrollView` + `LazyVStack(pinnedViews:)`，固定按钮、头部、继续卡片 / 开始按钮、简介、贴顶分区头与分段芯片、目录、横幅、骨架；
  小块拆到 `BookSiteDetailSections.swift`。
- `BrowseCraft/Features/Library/Book/Site/BookSiteDetailViewModel.swift`：读书历史、收藏、整站有声、登录态、目录派生状态（解析、显示顺序、分段、上次读到下标）、继续卡片文案、Locator 解析。
- `BrowseCraft/App/Composition/BookFeatureFactory.swift`：注入收藏用例、读书历史仓储、凭据存储。
- `BrowseCraft/Application/UseCases/Book/BookPublicationManifest.swift` 与 `BookPublicationAssembler.swift`：透传 `description`。
- `BrowseCraft/Features/Library/Comic/Detail/ComicDetailViewModel.swift`：`ComicChapterTitleParser` 加中文数字；单测补笔趣阁样例。
- 三份 `Localizable.strings`：「继续收听」「从第 1 章开始读 / 听」「全书 %@」「刚开始」「有声书 · %ld 章」「这本书还没有章节」「重试」；原英文字面换成键。
- 资产：不新增。

## 十三、真机验收清单与待接线

- 模拟器没走到：有声书（线上没有有声来源）、失败与登录横幅、没有章节、简介（规则都不给）。
- **待接线**：章节 `order` 到 Runtime 为止——Core 会读，`BookSourceRuntime.loadDetail` 构造 `SourceChapter` 时不带、也不按它排；等 fwq 交付「章节 `order`」需求后在 Runtime 接上并按它排序。
- 深色模式整页看一遍。
