# 添加来源页的视觉与信息结构重设计

设计稿（画布，含已登录、未登录、余额未同步、从目录页进入、深色，共 5 张）：
[添加来源页重设计](https://claude.ai/artifact/8oW72QWXgv6cVAQavmP5Vp)；设计文档：[添加来源页重设计](https://claude.ai/artifact/DLzUuWMHsotbMNRRa8mXFQ)。
设计与实施状态见 [STATUS.md](../STATUS.md)。颜色、圆角、字号与交互约定沿用来源页与规则目录页
（[来源页](Sources-Page-Redesign-Design.md)、[规则目录页](Catalog-Page-Redesign-Design.md)）。

## 一、背景

`AddSourceView` 曾是一个系统 `Form`：系统大标题「添加来源」、左上「取消」、一个分组标题「来源」，下面三行「漫画 / 视频 / 书籍」。

- 三行只有类型名，没说下一步要贴网址、要等服务器生成、要花 coin，也没说生成的规则先出现在规则目录「我的生成」里，而不是直接变成一个来源。
- 三枚圆形徽章（紫 = 漫画、蓝 = 视频、金 = 书籍）只在这一页用；其他页面的类型色是视频琥珀、漫画淡紫、书籍青绿（`CatalogKindStyle`），图标也不同。
- 类型顺序是漫画、视频、书籍；收藏页与历史页的筛选是视频、漫画、书籍。
- 系统表单样式与它的入口页（来源页、规则目录页）的自绘大标题和卡片不是一套；页面下方四分之三是空的。
- 选类型后在这层 sheet 上再弹一层 sheet，与「两个 sheet 不同时呈现」的约定不符。
- 未登录或 coin 不足，要等贴完网址、检查通过、点「生成规则」之后才知道。
- scriptSource 分支与「Source Type Unavailable」提示框从界面上到不了，提示是英文，还提到已下线的规则 JSON 导入（`BCA-UI-003`）。

## 二、入口、流程与范围

三个入口都以 sheet 弹出：来源页右上「＋ 添加」、来源页空状态「用网址生成」、规则目录页「我的生成」空状态（目录先收起，再弹出本页）。

从点「添加」到拿到来源的完整路径：

1. 选类型（本页）。
2. 合格入口页引导屏（`EntryPageGuideView`，首次必过一屏，`BC-PAGE-060`）。
3. 网址输入页（`VideoGenerationInputView`）：贴网址 → 检查网站 → 选取页方式 → 生成规则。
4. 提交成功后整个 sheet 收起，回到来源页。
5. 规则生成完出现在规则目录「我的生成」，用户在那里点添加，才占用一个来源位置。

**本文只覆盖第 1 步这一页，外加把三屏收进同一层 sheet**（2026-10-06 用户裁定七项全取 A）。引导屏与网址输入页的外观另立项，输入页优先。

## 三、页面内容

页面跟随系统深浅，底色与卡片底取系统分组背景，类型色与动作色全部取 `CatalogPalette` 与 `CatalogKindStyle`，不新增颜色。

| 从上到下 | 内容 | 取值与组件 |
| --- | --- | --- |
| 顶部 | 左上「关闭」；内容里自绘大标题「添加来源」 | `largeTitle` heavy 靠左，与来源页、目录页相同；页边距 20 |
| 一句说明 | 「贴一个网站列表页的地址，生成一条规则。先选这个网站属于哪一类。」 | `subheadline` 次级色 |
| 三张类型卡 | 顺序视频、漫画、书籍。每张：类型图标圆、类型名后带 ›、一句举例。举例：视频「影视、动漫、短片网站」，漫画「按章节看图的漫画网站」，书籍「小说与有声书网站」 | 规则目录页的类型横幅 `CatalogKindBannerView`：固定深色类型底 + 现有三张横幅插画，高 112，圆角 22，卡间距 12；整张可点，按下整张变暗。插画沿用目录页的三张，不新出图（2026-10-06 用户裁定） |
| 接下来 | 分区标题「接下来」+ 一张卡片三行：① 贴上带页码的列表页地址；② 检查通过后提交生成；③ 生成完出现在规则目录「我的生成」，从那里添加 | `SettingsCardGroup` 与 `SettingsRowSeparator`，32pt 图标方块；行不可点、无 › |
| coin 与登录 | 组下说明一行：已登录「生成一次 N coin 起 · 当前余额 M」；余额还没同步到时只写前半句；未登录「提交生成需要登录，可以在设置页登录。生成一次 N coin 起。」用警示色 | N 取服务端下发的普通档价格（`CoinWalletStore` 的 `pricing.normal`），不写死；`footnote`。只提示，不拦路：未登录也能点类型进去检查网址 |
| 另一条路 | 入口卡「从规则目录挑一个」「现成的规则，不用等生成」。点后本页先收起，再弹出目录。从目录页进来时不显示 | `SourcesEntryCardView`，与来源页空状态那张相同 |

- 选了类型之后，引导屏或输入页在同一层 sheet 里接着出现（条件渲染，不 push），不再叠第二层。输入页左上仍是「关闭」，关掉整个流程回来源页；输入页不能退回改类型，与现状相同。
- 这一页没有网络请求，没有加载、失败、空状态，不需要下拉刷新与新插画。
- 「关闭」替代原来的「取消」：这一页不取消任何事。

## 四、不改的东西

- 规则只来自服务端目录，App 不提供规则创建或编辑入口（`BCA-UI-003`）；本页只是生成入口。
- 引导屏的内容与「首次必过一屏」的规则（`BC-PAGE-060`）、输入页的检查与提交逻辑、取页方式与价格、提交成功后回来源页。
- 来源位置的判定：生成规则不占位置，从目录添加时才占，本页不提示位置。

## 五、实现位置

- `BrowseCraft/Features/Sources/AddSource/AddSourceView.swift`：整页重画；选类型后在同一层里换成 `EntryPageGuideFlowView`；删去 scriptSource 分支、不可用提示框与徽章图取值。
- `BrowseCraft/Domain/Models/Source/SourceImportOption.swift`：默认顺序改为视频、漫画、书籍；scriptSource 是否一并删除，实施时看 `RecommendSourceImportOptionUseCase` 与测试的引用再定。
- `BrowseCraft/Features/Sources/Catalog/CatalogStyle.swift`：`CatalogKindBannerView` 从目录页文件移到这里供两页复用，副标题可传入，可选在类型名后带 ›。
- `BrowseCraft/Features/Sources/SourcesView.swift`：本页请求打开目录时，等本页收起后再弹目录；从目录页进入时告诉本页不显示目录入口卡。
- 资源：删 ComicKindBadge、VideoKindBadge、BookKindBadge 三份图并撤掉 `scripts/bundled-image-asset-budgets.txt` 里的登记。
- 三份 `Localizable.strings`：新增说明、三句举例、「接下来」三行、coin 与登录两句、目录入口卡两句；删去不再使用的词条。
