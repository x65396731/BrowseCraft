# 规则目录页的视觉与信息结构重设计

设计稿（画布，含三个方向与方案 A 的全部状态页）：[规则目录重设计](https://claude.ai/artifact/MB3FwJqXykiuWbMj3ZA2aS)；
「发现」标签的设计稿：[规则目录推荐区改版](https://claude.ai/artifact/SrrBgFvcPSbwsnZdY4PxFg)，
设计书：[规则目录推荐区改版：站点示例与用户分享](https://claude.ai/artifact/Mv6Qq1JTHRTtNHbd8aN72y)；
添加中的等待与锁定（2.4 节）的设计稿：[规则目录添加中的等待与锁定](https://claude.ai/artifact/KYHi6jbr8H1CEfvtkXH6mJ)，
设计书：[规则目录添加中的等待与锁定设计书](https://claude.ai/artifact/Fpv5cXHuTCBwPFJ6R92i1V)。
本文以方案 A 为推荐方向陈述；方案 B、C 作为备选列在第五节。设计与实施状态见 [STATUS.md](../STATUS.md)。

## 一、背景

`CatalogSourceListView` 是一个朴素的分组 List：「我的生成」与「默认数据」两个 Section 上下排列，
每行只有「名称 + 类型 · 完整 URL」两行文字与一个 `plus.circle`。存在三个问题：

- **自己的与客户端推荐的混在一条滚动里。** 个人规则一多，推荐内容被压到很下面；两者的用途不同
  （个人规则有 7 天保留期、可左滑删除，推荐没有），却共用同一种行。
- **推荐内容没有按类型组织。** 视频、漫画、书籍按服务端返回顺序混排，类型只体现在副标题的两个字上。
- **个人规则的时间感弱。** 成功规则与失败任务是两个独立的 `ForEach`（`personalCatalogSources` 在前、
  `failedGenerationOutcomes` 在后），用户看不出哪条是刚生成的；剩余时间只是一行小字。

公共目录原本是开发者下发、所有用户都能看到的影视 / 漫画 / 小说站。App 以「网站是用户自己选的」工具姿态送审，
对外不预置这类站点：原「推荐」标签改名「发现」，版式不变，Release 构建只展示内容版权没有疑问的站点示例（2.2）；用户分享另行上线（2.6）。

## 二、信息结构（方案 A）

### 2.1 两个标签

- 页面顶部是大标题「规则目录」，其下一个两段的分段控件：**✦ 发现** | **我的生成**（即原「推荐」，只改名，图标仍是 ✦）。
  「我的生成」段带数量角标，数值为个人成功规则与失败记录之和；为 0 时不显示角标。
- 打开目录页时「我的生成」有条目就落在「我的生成」，否则落在「发现」（2026-10-09 用户裁定：自己的生成优先）。
  条目数要等首次拉取回来才准：打开时先按已有数据定段，首次拉取完成后按同一规则再定一次；用户在此之前已经自己点过分段的，不再替用户改段。
  两个标签共用一个 `refreshCatalogSources`：每次呈现与下拉刷新都重新拉取，不因切换标签而单独拉取。
- 刷新与重试一律用下拉手势，不加刷新按钮；空状态与失败状态的可发现性做在文案与下拉示意上。

### 2.2 发现：站点示例与内部测试

「发现」自上而下两块，数据都取公共目录、按 `section` 分开；没有 `section` 字段或取值不认得的条目一律不展示。

- **站点示例**（Release 与 Debug 都有）：取 `section` 为 `example` 的条目，保持服务端返回顺序，最多 6 条，不按类型分区。
  示例可以由某个用户生成的规则转来，所以**不按本人生成 id 剔除**：生成者本人在 7 天可见期内会在「发现」与「我的生成」两边看到同一条，这是预期。
  - 示例只收内容版权没有疑问的站点（公有领域作品、政府公开作品，或使用条款明确允许转载与聚合的站点），
    由服务端目录侧经 fwq 生成后配置，本文不列站名；不另建演示站。
  - 分区标题「站点示例」按统一分区标题（`footnote` 粗体次级色，左右 24pt），右侧写条数「N 个」。
  - 列表是一组「卡片行组」：同组的行拼成一张圆角 18 的卡片，行间细线从 68pt 起；每行 42pt 首字徽标 + 站点名
    （`subheadline` semibold，单行截断）+「类型 · 主机名」（`caption` 次级色），行尾是添加动作（2.4），不放 ›。不显示分类行与标签。
- **内部测试**（只在 Debug 构建）：取 `section` 为 `internal` 的条目（原预置站点，服务端只返回给白名单账号）。
  分区标题「内部测试」，下方一行 `caption`「仅 Debug 构建，仅白名单账号」；内容沿用原「推荐」的版式，规则如下。
  Release 构建里没有取用 `internal` 的代码路径。
- 内部测试的条目按 `kind` 分区，分区顺序固定为 视频 → 漫画 → 书籍；
  某类型没有条目时整个分区不出现。区内保持服务端返回顺序。
- 每个分区由两部分组成：
  - **类型横幅**：通栏（宽随屏，左右页边距内撑满）× 高 112、圆角 22，底色为该类型的深色底，左下是类型图标圆 + 类型名 + 「左右滑动查看全部」，
    右侧是该类型的插画（第四节）。
  - **横滑卡片带**：卡片 180×244、圆角 18。自上而下：首字徽标（36×36，类型色 16% 底 + 类型色字）一行、
    标签靠右（放不下时靠右竖排）；站点名独占整行、最多两行；副标题地址独占一行；分类行；底部一个通栏按钮。
    站点名不与徽标并排——并排时名字只剩约 90pt，「站名 · 分类」这类名字一截就看不全。
    卡片带左右留 20pt，最后一张露出一截，提示可以横滑。
- 副标题地址沿用 `catalogEntryURL(for:)` 的取值规则（同站多条取各自入口，否则 `baseURL`），但只显示主机名，
  并去掉 `www.` 前缀；同站多条时显示主机名 + 路径的尾段，保证能区分。
- 分类行与标签行来自规则本体（`CatalogRuleFacts`，目录读到时逐条解析一次）。目录接口只给
  id / name / baseURL / kind / ruleJSON，其余信息只能取自规则；三种 kind 用同一套 JSON 路径，不按 kind 分支。
  - **分类**：可浏览列表页（`list` / `category` / `series`）的 `title`，去重去空。两个及以上写「N 个分类」+ 前三个名称，
    其余写「+N」；只有一个时写「分类」+ 该名称；没有时整行不出现。
  - **可搜索**：`ruleSets.searchRules` 非空时显示。
  - **语言**：`site.language` 归一后与 App 当前界面语言不同才显示。中文按文字分简繁——显式 script 优先，
    没有时台港澳地区视为繁体，`zh` 与 `cmn` 同属中文；简繁用「简中 / 繁中」，其他语言用系统本地化的语言名。
  - 不展示：站点图标（线上规则 `site.iconURL` 全部为空）、登录需求（用户裁定不展示）。

### 2.3 我的生成：按时间的时间线

- 成功规则与失败记录**合并为一条时间线**，按 `VideoGenerationOutcome` 的 `finishedDate` 倒序，最新在上；
  按自然日分组，组头为「今天」「昨天」，更早的写「M月d日」（跨年带年份）。没有 `finishedDate` 的记录排在最后一组「更早」。
- 时间线上方是保留期说明卡片，文案沿用 `catalog_personal_retention_hint`。
- **成功规则卡片**：首字徽标 + 名称（最多两行）+ 「主机名 + 灰色路径」单行截断；右侧是动作按钮；
  下方一条保留期进度条，长度为剩余时间占 7 天的比例，右侧是 `personalRuleRemainingComponents` 给出的剩余文案。
  剩余不足 1 天时进度条与文案改用警示色。
- **失败记录卡片**：警示色描边与底色，左侧警示图标，右侧依次是「生成失败」小标签 + 入口 URL、`reason` / `reasonDetail` 文案；
  只有首页 / 根入口类拒因（`reasonDetail` 落在 `VideoGenerationOutcomeText.entryGuideDetails`，现只有 `entryPageIsSiteRoot`）时追加「看看怎样的页面能生成」链接，打开 `EntryPageGuideView`；
  其余拒因只陈述成因、不叫用户换页（fwq `APP-MEMO-045`），`entryPageRejectionDetails` 只用于并进已知拒因集合。
- 两种卡片都保留左滑删除（`deletePersonalRule` / `deleteFailedGenerationOutcome`），删除按钮为通高红色块。
  失败记录按入口 URL 去重、只显示最近一次，所以左滑删除失败记录时把同一入口的全部失败一起软删除；
  服务端终态接口的上限随之提高，条数由 7 天可见期限住，不再出现「删一条、更早一条补位」。
- 两种卡片都**不显示**服务端随终态下发的 `aiTokens` / `cloudCost`（2026-10-11 裁定）：用户付的是固定价 coin，这两个数是 Provider 用量与云端实扣，
  对用户没有可据以行动的意义，`cloudCost` 还是经营侧成本；推送负载与 `/outcomes` 的解码按现状忽略它们。重开条件见 `docs/STATUS.md` 第 2 节该行。

### 2.4 条目动作的四种状态

由 `CatalogAddActionState` 表达，判据依次是：这一条正在添加 → 已在库里 → 另一条正在添加 → 未添加：

| 状态 | 内部测试卡片（通栏按钮） | 站点示例行（行尾）与我的生成卡片（右上） |
| --- | --- | --- |
| 未添加 | 实心蓝「+ 添加」 | 36pt 实心蓝圆形「+」 |
| 添加中 | 灰底胶囊内系统小转圈 + 文字按钮「取消」 | 系统小转圈 + 文字按钮「取消」（添加蓝，热区不小于 44pt） |
| 已添加 | 灰底「✓ 已添加」，不可点 | 灰底小胶囊「✓ 已添加」 |
| 另一条正在添加 | 「+ 添加」换禁用色，不可点 | 「+」换禁用色（`CatalogPalette.disabledAction`），不可点 |

添加中的那一条在副标题下多一行 caption 次级色「正在验证这个网站…」，与失败文案同一位置。指示器保持系统小转圈：
它在按钮位置、不足 44pt，属于 `BCA-UI-007`「不放」品牌等待标记的一类。

**添加中只锁本页相关操作，不加全屏遮罩**（`BCA-UI-007`）：同一时刻只添加一条，其余「+」暂不可点、不排队；
左上「关闭」不可点，sheet 禁止下滑关闭，「我的生成」空状态里会收起目录的「去添加来源」也不可点；分段切换与上下滑动照常。
添加一条新来源要用这条规则真的取一次网站第一页，等待几乎全在这一步，长短取决于网站本身。

- **取消**：停止这次添加，这一条恢复「+」，其余恢复可用，不写失败文案，不报 `source_added`。
- **总时限 45 秒**：到点停止这次添加、这一条恢复「+」、其余恢复可用，并追加警示文案「这个网站太久没有响应，请稍后再试。」；与取消不同，超时仍报 `source_added` failed（`error_code` 为 network，见埋点合同）。
- **取消与超时做到底**：规则请求的公共通道（`AlamofireHTTPClient`）随任务取消中断请求，WebView 取页本来就响应取消；
  `AddCatalogSourceUseCase` 存库前再查一次是否已取消，所以取消或超时后即使第一页晚到也不入库，用户不会看到「取消了却加上了」。

添加成功即关闭目录页并切到库标签选中新来源（`CatalogSourceListView` 在 `addCatalogSource` 返回成功后 `dismiss()`），用户在那一刻看不到「✓ 已添加」；这一态只在重新打开目录、条目已在库里时出现。失败则留在页上，由下一段的失败文案承担。

两边都没有「更新」状态：规则变了由 App 自动覆盖本地副本——公共目录来源见
[Catalog-Rule-Update-Design.md](Catalog-Rule-Update-Design.md)，个人规则由 `refreshPersonalSourcesFromOutcomes` 覆盖。

添加失败时在卡片底部追加一行警示色的失败文案（`catalogSourceAddFailureMessages`），不弹窗。

### 2.5 加载、空与未登录

| 场景 | 判定 | 显示 |
| --- | --- | --- |
| 发现 · 加载中 | `isLoadingCatalogSources` 且目录为空 | 「站点示例」标题照常显示，下面一张三行的卡片行组骨架（徽标、两行字、圆形按钮的色块），底部「加载中…」 |
| 我的生成 · 加载中 | 已登录、时间线为空且 `isLoadingCatalogSources` | 整页一个系统转圈 + 「加载中…」，不用骨架 |
| 发现 · 空 | 加载结束且没有示例（Debug 下也没有内部测试条目） | 空书架插画 + 「暂无目录数据」+ 一句说明 + 向下箭头与「下拉可重新加载」 |
| 我的生成 · 未登录 | `isPersonalCatalogSignInRequired` | 上锁书箱插画 + 「登录后查看」+ `catalog_personal_sign_in_hint` + 「到「设置」里用 Apple 登录」的指引（登录入口在设置页，目录页不另设登录按钮） |
| 我的生成 · 空 | 已登录，成功与失败都为空 | 空白画布插画 + 「还没有生成过规则」+ 指向「添加来源」的说明，主按钮「去添加来源」（目录页收起后由来源页打开添加来源），次链接「怎样的页面能生成？」 |

现状在「已登录但没有任何任务」时整个个人分组不显示；改为分栏后该标签必须有内容，因此改为显示上表的空状态。

### 2.6 用户分享（不在本版）

让用户把自己生成的规则公开给所有人的「用户分享」不在本版。上线时在「发现」里另起分区，已定的约束：

- 分区写明「其他用户分享的站点规则」，并有一句说明：由用户分享，App 不提供也不审查网站内容，发现侵权可举报。
- 不显示分享者身份。
- 举报（侵权 / 色情或违法 / 已失效）与「屏蔽此分享者」放在每张分享卡片右上的「···」菜单；举报后该卡片在本机立即隐藏。
- 上线前必须同时具备：服务端的发布前过滤与人工复核、举报处理与版权投诉下架、按账号的屏蔽名单、公开的投诉联系方式
  （设置页一行，与 App Store 技术支持网址一致）；App Store Connect 年龄分级问卷的「用户生成内容」改为「是」后重新保存。

## 三、视觉规范

- **基调**：目录页跟随系统外观，与弹出它的来源页一致——页面之间的主题色不能差异过大，浅色页面上弹出整张深色页反差过大。
  页面与卡片底色取系统分组背景，深浅色自动跟随；类型色、动作色与警示色的唯一声明点在 `CatalogKindStyle` 与 `CatalogPalette`，
  两套取值都随系统。Features 层不直接写 `.white` / `.black` / `Color(uiColor:)`：实心按钮上的字用 `onAction`，类型色底上的字用 `onAccent`（浅色白、深色墨），反色元素上的字用 `onPrimary`，非分组页面底 `plainBackground`，分隔线 `separator`，按下态 `pressedFill` / `pressedScrim`，阴影 `shadow` / `cardShadow` / `posterShadow`，封面上的黑 `coverScrim` / `coverShade` / `badgeScrim` / `headerScrim`，固定深色瓷砖上的半透明白 `onDarkFill`（统一 16%）。仍允许直接写颜色的只有功能性取值，清单以 `CatalogPalette` 的注释为准。**类型横幅永远是深色色块**：插画本身是深底，横幅的底色、图标圆、标题与说明文字
  都取固定的深色取值、不随系统变；浅色页面上它就是三块深色类型色块，与来源页「正在使用」的深色类型瓷砖同一种做法。
  页面、卡片、次级填充与分段控件全部取系统色（`systemGroupedBackground`、`secondarySystemGroupedBackground`、`tertiarySystemFill`），不另写深色值。
- **文字**：随系统（`.primary` / `.secondary`）；横幅上的标题 #F4F3EF 是本页唯一固定的文字色（深色头图与沉浸播放页上的白字见各自合同）。字体用系统字体。
- **类型色**（`CatalogKindStyle.accent`，浅 / 深）：视频 #A85A12 / #F2A65A（琥珀）、漫画 #6D4FD6 / #B79CFF（淡紫）、书籍 #1E7D68 / #5CC8B0（青绿）；横幅等固定深色处只用深值。类型之间同时用图标区分，
  不只靠颜色：视频为播放三角、漫画为对话气泡、书籍为书本。
- **动作色**：添加 #2563EB（白字对比度满足 4.5:1，不随系统）；警示浅色 #C2410C / 深色 #FF8A70（`CatalogPalette.warning`，淡底取其 14%）；删除 #E5484D。
- **圆角**：横幅 22，卡片 18，首字徽标取边长的 0.29（36pt 徽标约 10、42pt 约 12），胶囊按钮取高度的一半。触控目标不小于 44pt（通栏按钮与圆形按钮用外扩热区补足）。
- 首字徽标取站点名的第一个字符；是拉丁字母时取大写。

## 四、插画资产

插画由极梦生成，画面内不含文字。空状态沿用 App 既有空状态插画的看板娘（银色长发、黑白服装带青色光点的 Q 版二次元角色）；
横幅不放人物——112pt 高的横幅里人物只剩一个小头像，还与左侧类型名争视线——改用每类一个 3D 软陶质感的单物体。
空状态插画与既有那批同规格：透明底、540px 高、按 180pt 显示；横幅铺满、不透明，物件只占右侧约四分之一，左侧三分之二纯色留给文字；按最宽机型（400pt 宽）出 1200px，窄屏两侧被裁，
主体离左右边缘各留一成余量。
每个 imageset 只有一个 universal 单槽位（无 scale 后缀，像素尺寸见下表与 `scripts/bundled-image-asset-budgets.txt`），进资源目录，不从网络加载。资产名固定如下；资源目录里还没有这张图时，横幅退回纯色底 + 图标，空状态退回系统符号，
不需要改代码。

| 用途 | 尺寸（像素） | 主体 |
| --- | --- | --- |
| 视频横幅 `CatalogBannerVideo` | 1200×336 | 右侧一个立体场记板（琥珀与黑色条纹），微倾、被右缘切掉一截，暖色光晕，底色 #2B2117 |
| 漫画横幅 `CatalogBannerComic` | 1200×336 | 右侧一组立体对话气泡（一大两小加一个爆炸形），淡紫与白，微倾、被右缘切掉一截，底色 #221E33 |
| 书籍横幅 `CatalogBannerBook` | 1200×336 | 右侧一本立体翻开的精装书，青绿丝带书签垂下，微倾、被右缘切掉一截，底色 #152A26 |
| 发现 · 空 `CatalogEmptyRecommended` | 高 540，宽随构图，透明底 | 看板娘抱着空纸箱、望向空书架，略带困惑 |
| 我的生成 · 空 `CatalogEmptyPersonal` | 高 540，宽随构图，透明底 | 看板娘举着发光的笔，面前一张空白卡片，笔尖洒出三种类型色的光点 |
| 我的生成 · 未登录 `CatalogPersonalSignIn` | 高 540，宽随构图，透明底 | 看板娘双手捧着一只上锁的小宝箱，另一侧悬着一把钥匙 |

空状态插画以纯白底出图，抠成透明底后裁边、缩到 540px 高。横幅原图为 21:9，物件几乎占满高度，直接裁成 1200×336
会切掉物件上下两端，因此整张等比缩到 336px 高、靠右放，左侧用原图左缘背景的平均色补齐并渐变过渡；物件离右缘不足
一成时整张左移、右侧同样补齐，保证窄屏两侧被裁时物件完整。

插画缺失时横幅退回纯色底 + 图标，页面不依赖插画才能成立。

## 五、备选方向

- **方案 B · 杂志封面**：单页滚动。顶部一张全宽头图与衬线大标题；其下「我的生成」为横向卡片带（最新在前，带剩余时间胶囊与「全部」入口）；
  再下是「推荐」，顶部一排类型筛选（全部 / 视频 / 漫画 / 书籍），内容为按类型分组的两列网格。氛围感最强，最依赖插画质量。
- **方案 C · 原生分组升级**：保留分组 List 结构，加首字徽标、胶囊按钮、顶部类型跳转条与分组标题小图标；
  「我的生成」行内显示「日期 · 剩余时间」。改动最小。

## 六、不变的部分

- 删除、失败记录与入口页教程的行为与判据不变；添加中的锁定、取消与总时限见 2.4。规则更新是自动的，界面上没有入口。
- 两个分组的数据来源：`CatalogSourceGrouping` 的 `defaultSources`（按 2.2 的 `section` 规则筛过）/ `personalSources` / `failedOutcomes`；公共目录条目的解码多读一个 `section` 字段。
- 终态里的用量字段（`aiTokens` / `cloudCost`）不进 App 的端口模型，也不进任何页面（见 2.3 末条）。
- App 不提供规则创建或编辑入口（`BCA-UI-003`）；「去添加来源」只是跳到既有的添加来源流程。

## 七、实现位置

- `BrowseCraft/Features/Sources/Catalog/CatalogSourceListView.swift`：分段控件、两个标签的内容、统一分区标题 `CatalogSectionHeaderView`、站点示例行 `CatalogExampleRowView`、行尾添加动作 `CatalogRowAddControl`（示例行与我的生成卡片共用）、内部测试卡片、首字徽标视图 `CatalogMonogramView`、骨架与状态页；内部测试分区的视图只在 `#if DEBUG` 里。
- `BrowseCraft/Features/Sources/Catalog/CatalogPersonalTimeline.swift`：个人时间线的合并排序与按日分组（`CatalogPersonalTimeline`），内部测试按类型分区（`CatalogKindSection`）。
- `BrowseCraft/Features/Sources/Catalog/CatalogStyle.swift`：配色、类型样式、首字徽标与地址的显示取值，以及与添加来源页共用的类型横幅 `CatalogKindBannerView`。
- `BrowseCraft/Features/Sources/Catalog/CatalogRuleFacts.swift`：推荐卡片的分类 / 可搜索 / 语言取值与语言归一（`CatalogLanguage`）。
- `BrowseCraft/Features/Sources/SourcesViewModel.swift`：`personalCatalogTimeline`、`personalCatalogItemCount`、`personalRuleRemainingFraction(for:)`、`catalogRuleFacts`。
- `BrowseCraft/Features/Sources/SourcesView.swift`：「去添加来源」在目录页收起后打开添加来源。
- `BrowseCraft/Application/UseCases/Generation/CatalogSourceGrouping.swift`、`BrowseCraft/Domain/Models/Source/CatalogSource.swift`、`BrowseCraft/Application/UseCases/Source/AddCatalogSourceUseCase.swift`：`section` 的解码（明文字段，解密后带到 `CatalogSource.section`，不认得的取值为 nil）与按构建筛选（`CatalogSourceGrouping.exampleSources` 最多 6 条、`internalSources` 只在 Debug 收）。
- `Localizable.strings`：标签名、类型横幅、日期分组、空状态与未登录的文案键。
- 固定输入：`BrowseCraftTests/Features/Sources/CatalogPersonalTimelineTests.swift`、`CatalogSourceGroupingTests.swift`（`section` 筛选）、`PersonalRuleRetentionTests.swift`（本人生成转成示例后两边都在）、`SourcesViewModelTests.swift`（添加超时与取消）。

## 八、真机验收清单

- **第一次打开**（目录还没加载完）时标题与分段控件不向左溢出。这个问题只在加载骨架出现时触发，冷启动后直接打开目录最容易看到。
- 浅色与深色下六张插画的观感。
