# 新手引导

设计稿（画布，上排 v1 共 8 张；下排 v2 视觉重设计共 8 张：欢迎卡浅 / 深、三步、第 3 步深色、库页一步、取值板；用户 2026-10-24 裁定六项全取 A）：
[新手引导设计稿](https://claude.ai/artifact/PeMDXENKHakku2SdMZjycK)；设计文档：[新手引导设计书](https://claude.ai/artifact/CFensej5PMBCN7cv8HDrwS)。
设计与实施状态见 [STATUS.md](../STATUS.md)。流程、聚光目标与出口沿用来源页与设置页的交互约定
（[来源页](Sources-Page-Redesign-Design.md)、[设置页](Settings-Page-Redesign-Design.md)），引导盖在其上的页面版式不因它改变；
引导层自己的颜色是品牌墨青 + 青绿 + 多彩渐变（第八节），与等待标记（[Brand-Waiting-Mark-Design.md](Brand-Waiting-Mark-Design.md)）、
引导屏困难档（[Generation-Input-Page-Redesign-Design.md](Generation-Input-Page-Redesign-Design.md)）同一种语言，不用系统蓝胶囊。

## 一、背景

首次安装的用户看完开屏视频就落到空的来源页：插画、「还没有来源」、一句说明、两张入口卡。页面没有说 App 能看什么、底栏五页各是什么、
第一步该走目录还是网址生成；已有的两处引导（合格入口页引导屏、新注册欢迎页）都在生成那一支里，不是 App 介绍。

参考的是市场上常见的页内引导：先一张卡说来意，再把真实页面压暗、聚光灯挖空当前要讲的控件、气泡说一句话，最后一步没有按钮，
只把真实控件亮着让用户自己点，点完引导结束、用户顺手完成了第一个真实动作。不做独立的横滑介绍页。

- `BCA-UI-009` 新手引导只以「聚光灯气泡层」盖在真实页面上呈现，不做独立介绍页，也不经 In-App Messaging。引导层不持有页面逻辑、
  不改变任何页面的版式与数据：页面只用 `spotlightTarget` 登记聚光目标，并在入口卡被点时告知引导；每一步都可跳过；
  最后一步的出口是用户点真实控件，控件的原动作照常执行。它只在本机没有来源且没看过当前版本时出现，已有来源的用户不弹。

## 二、形式、时机与范围

- 时机：开屏动画点「跳过」落到来源页之后盖上欢迎卡；开屏视频不改。
- 谁会看到：本机没有来源且 `onboardingSeenVersion` 小于当前版本。iCloud 首次恢复还没完成时本机库也是空的，按「没有来源」算，照弹。
- 库页的一步另有触发：第一个来源添加成功、自动切到库、库页登记了第一张封面之后给一次；只给一次。
- 不改：开屏动画与它的跳过规则、来源页空状态与两张入口卡、库页版式、合格入口页引导屏、新注册欢迎页、登录与 coin 的逻辑、
  系统权限的申请时机（跟踪授权只在看激励广告前申请，通知只在生成提交与活动推送开关时申请）。
- 它不是活动类提示，不走 In-App Messaging（`BCA-UI-004` 只管活动弹窗与欢迎页），由 App 自绘。

## 三、引导层的结构

一层盖在根视图的 `TabView` 上（开屏层之下），由三样东西组成：蒙层、聚光灯挖空、气泡（步号行右侧带「跳过」）。

- 蒙层：`CatalogPalette.tourScrim`（墨青调 72%，深色黑 78%），盖住整屏含底栏；蒙层上的点击一律吞掉，只有「请用户点」的那一步挖空区透过去。
- 聚光灯：按目标控件的外接矩形外扩 8pt 挖空，圆角取目标圆角 + 4，沿挖空描 2pt 多彩渐变并加一圈同色外发光（亮着的控件像被打光；
  深色下蒙层与页面都近黑，靠它看出哪块亮着）；请用户点的那一步再加一圈青绿细外环呼吸。换步时挖空从上一个矩形动画到下一个
  （系统「减弱动态效果」打开时直接切，外环也不呼吸）。挖空内的控件保持原亮度。
- 气泡：卡片底、圆角 20、内边距 18、左右距屏 20、墨青投影，一枚 16pt 三角指针指向目标；放在目标下方，下方放不下就放上方。
  内容自上而下：步号行（左三段进度条 + 「1 / 3」`caption` 次级色，右「跳过」`footnote` semibold 次级灰文字按钮，触控区 44 × 32）、
  正文块（左 40pt 墨青圆配青绿线性图标，右小标题 `headline` + 正文 `subheadline`）、
  一个墨青实心胶囊按钮高 48 带青绿箭头（「下一步」/「知道了」）；请用户点的那一步没有按钮，换成一句多彩渐变字的提示「点亮着的卡片继续」+ 青绿向下箭头。
- 「跳过」只在有步号的三步里出现；欢迎卡有自己的「跳过」文字按钮，库页那一步没有（「知道了」就是关闭）。它不浮在蒙层上，
  免得压在标题行的计数或按钮上。
- 目标由页面上的视图用 `spotlightTarget(_:isActive:)` 登记（`SpotlightAnchorKey`），根视图读到矩形后画挖空与气泡。
  底栏不是 SwiftUI 子视图，矩形按安全区底部 + 49pt 算。目标还没登记（页面还在加载）时这一步不画挖空，气泡停在屏幕下方。

## 四、每一步的内容

| 步 | 在哪页 | 聚光目标 | 气泡文案 | 结束方式 |
| --- | --- | --- | --- | --- |
| 0 欢迎卡 | 来源页空状态上 | 无（整屏蒙层 + 居中卡） | 标题「把常看的网站装进来」；正文「AnyPortal 自己不放内容。你添加一个网站，它的视频、漫画或书就整理进库里。先带你看一圈，再加第一个网站。」 | 「开始」进第 1 步；「跳过」文字按钮结束 |
| 1 / 3 | 来源页 | 空状态块（插画 + 「还没有来源」+ 一句说明）；回看形态为「正在使用」卡 | 「来源就是一个网站。添加一个，它的内容就按视频、漫画、书籍整理成库。网站是你自己选的。」 | 「下一步」 |
| 2 / 3 | 来源页 | 底栏整条 | 「常用的是这三个：来源管网站，库看当前网站的内容，历史接着上次看。登录、coin 和 iCloud 同步在设置里。」 | 「下一步」 |
| 3 / 3 | 来源页 | 两张入口卡（一个挖空包住两张）；回看形态为右上「✦ 目录 \| ＋ 添加」胶囊 | 「两条路加第一个网站：目录里挑现成的，或贴网址生成（要登录，新账号有赠送的 coin）。」+ 提示「点亮着的卡片继续」 | 没有按钮；用户点任一张卡，引导结束，卡片的原动作照常执行 |
| 库页 | 第一个来源进库后 | 第一张海报（含爱心与标题）；漫画库、书籍库是第一张封面 | 「第一个网站进来了。点封面打开作品，右上角的爱心收藏；看过的会出现在历史里，点一下接着看。」 | 「知道了」；库页第一页没有内容或加载失败时不给这一步 |

第 3 步挖空里两张卡都能点，不替用户选路；之后的规则目录、添加来源、引导屏、网址输入页都是现有链路。

气泡每步有一行小标题与一枚图标（2026-10-24 裁定 1 取 A）：第 1 步「来源 = 一个网站」（回看形态「正在使用的网站」）/ 地球，
第 2 步「常用的是这三个」/ 底栏，第 3 步「加第一个网站」（回看形态「再加一个网站」）/ 加号，库页「第一个网站进来了」/ 爱心。
欢迎卡正文下方多一行三枚类型胶囊（视频 / 漫画 / 书籍，取 `CatalogKindStyle` 的图标与 `accent`，词条沿用 `Video` / `Comics` / `Books`；裁定 2 取 A），
上半段色块底部一行「ANYPORTAL」字样（裁定 6 取 A，品牌名不翻译）。

## 五、出口与之后

| 出口 | 落点 |
| --- | --- |
| 欢迎卡「跳过」、任一步右上「跳过」 | 蒙层收起，来源页空状态（现状）；库页那一步不再给 |
| 第 3 步点「从规则目录挑一个」 | 蒙层收起，来源页照常弹规则目录（落「发现」） |
| 第 3 步点「用网址生成」 | 蒙层收起，来源页照常弹添加来源页 |
| 库页「知道了」 | 蒙层收起，留在库页 |

- 第 3 步只是让挖空内的点击透过去，卡片自己的动作照跑；来源页在卡片动作里调一次 `OnboardingTourStore` 的告知，其余逻辑不动。
- 从第 3 步走出去的用户若在目录或添加来源页关掉了 sheet、没加成，回到来源页不再重新引导（已记为看过）；库页那一步仍等第一次加成后给。
- 库页那一步等待期间用户离开库标签，这一步作废。

## 六、跳过、回看与版本

- 关闭即记为看过，不论从哪一步离开：来源页部分写 `onboardingSeenVersion`，库页部分单独写 `onboardingLibraryHintSeen`。
  文案实质改版时 `OnboardingGuide.currentVersion` +1 让老用户再看一次；只改错别字不动。已有来源的用户无论版本号都不弹。
- 回看：设置页「关于」组首行「新手引导」›，点了切到来源标签重放欢迎卡与三步。此时页上多半已有来源，每一步的聚光目标有备选：
  第 1 步空状态块 → 「正在使用」卡（文案换成「正在使用的网站在这里，点卡片打开它的库」）；第 3 步两张入口卡 → 右上胶囊
  （文案换成「再加一个网站从这里：目录里挑现成的，或贴网址生成」）。库页那一步在下次进库时再给一次。
- 判定在 `OnboardingGuide.shouldPresent(seenVersion:hasSources:)`，单独可测；视图不自己读来源表。
- DEBUG 启动参数 `-BrowseCraftShowOnboarding` 强制重放（演示模式种了来源，模拟器里不加它看不到；截图也从这里出）。

## 七、埋点与本地化

不新增页面名（引导盖在哪页就算哪页），一个事件，不新增 GA4 参数；词条各语言齐全。

| 项 | 取值 |
| --- | --- |
| 事件 | `onboarding_finished`：来源页部分结束时报一次，库页那一步结束再报一次 |
| `entry` | `OnboardingEntry`：`first_run` / `help` |
| `result` | `OnboardingResult`：`catalog` / `generate` / `library_done` / `skipped_welcome` / `skipped_1` / `skipped_2` / `skipped_3` |

- 事件字典与中文注释登记在 [Analytics-Events-Design.md](Analytics-Events-Design.md) A 组（`BCA-OBS-001`）；统计开关关闭不报（`BCA-OBS-005`）。
- 词条各语言各一份：欢迎卡标题与正文、三步正文（第 1、3 步各一句回看备选）、三步小标题（第 1、3 步各一句回看备选）、库页正文与小标题、
  「开始」「下一步」「知道了」「跳过」、第 3 步提示句、步号格式、设置行「新手引导」。气泡正文允许四行，放不下时换到目标另一侧。

## 八、视觉取值

v2（用户 2026-10-24 裁定六项全取 A）：引导层不用系统蓝胶囊与白卡，改品牌墨青 `brandWaitingFill` #0E1D25 + 青绿 `tourAccent` #5CC8B0
（书籍横幅强调色，也是看板娘手里光标的颜色）+ 饱和多彩渐变 `spectrumVividGradient`；新取值都加在 `CatalogStyle.swift`，页面里不写死色值。
v1 旧值记在括号里，便于对照。

| 项 | 取值 |
| --- | --- |
| 蒙层 | `CatalogPalette.tourScrim`：墨青 #08121A 72%，深色黑 78%（v1 黑 55% / 65%，太轻，挖空不够亮；裁定 5） |
| 挖空 | 目标矩形外扩 8pt；圆角 = 目标圆角 + 4（入口卡 18 → 22，空状态块 18，「正在使用」卡 24 → 28，底栏 12）；沿边 2pt `spectrumVividGradient` 横向描边 + 同渐变 10pt 描边经 7pt 模糊、60% 的外发光（`tourGlowOpacity`），外发光只向挖空外扩（挖空内遮掉，不压到目标里的文字）；请用户点的那一步再加 1.5pt `tourAccent` 45% 外环，外扩 7pt，1.6 秒呼吸一次（外扩 0 → 7pt 来回），减弱动态效果时静止（v1 1pt `onDarkFill`；裁定 4） |
| 气泡 | `cardBackground`，圆角 20，内边距 18，左右距屏 20，指针 16pt；投影 `tourBubbleShadow`（墨青 38%，半径 22，y 10）；深色下加 1pt `onDarkFill` 描边；步号行左三段 26 × 5 进度条（已到段 `spectrumVividGradient`，未到段 `fillBackground`，间距 5）+ 「n / 3」`caption` semibold 次级色；正文块左 40pt `brandWaitingFill` 圆 + 20pt `tourAccent` 线性图标 + 3pt `tourAccent` 22% 光环，右小标题 `headline` + 正文 `subheadline`（v1 无小标题与图标；裁定 1） |
| 气泡按钮 | 墨青实心胶囊高 48：`brandWaitingFill` 底、白字 `subheadline` semibold + 16pt `tourAccent` 箭头；深色反色（`tourButtonFill`：白 94% 底、墨青字）（v1 `addAction` 白字高 44；裁定 3） |
| 第 3 步提示句 | `footnote` bold 多彩渐变字（`spectrumVividGradient` 做遮罩）+ 16pt `tourAccent` 向下箭头（v1 动作蓝 semibold） |
| 「跳过」 | 气泡步号行右侧，`footnote` semibold 次级灰（`.secondary`），触控 44 × 32（v1 `caption` 动作蓝） |
| 欢迎卡 | `cardBackground`，圆角 28，左右距屏 24，裁切；上半段 208pt `brandWaitingFill` 色块：右上 240pt 青绿径向光圈（`tourAccent` 34% → 0）、左下 220pt 紫光圈（`spectrumVividColors[1]` 30% → 0）、居中 136pt 圆形 `BrandWaitingPoster` 海报帧 + 3pt `tourAccent` 35% 光环 + 40pt 同色外发光、底部「ANYPORTAL」`caption2` semibold 字距 3 `immersiveSecondaryText`（白 68%）；下半段内边距 24 / 22：标题 `title2` heavy、正文 `subheadline` 次级色、三枚类型胶囊（高 30，`accent` 字 + 12% 底 + 20pt 同色圆白图标）、「开始」52 高 `spectrumVividGradient` 胶囊 + 白字 `headline` + 白箭头 + 紫 38% 投影（`tourPrimaryShadow`）、「跳过」`subheadline` semibold 次级灰 44 高（v1 白卡圆角 22、64pt 圆图、`addAction` 50 高胶囊；裁定 2、3、6） |

不出新插画；设置行图标沿用 `SettingsOnboarding`，设置页「关于」组回看行与设置页其余行同一种样子，不随 v2 变。

## 九、裁定

裁决叙事见 [status-log.md](../history/status-log.md)。

## 十、实现位置

- `BrowseCraft/Features/Shared/SpotlightTourOverlay.swift`：蒙层 + 挖空 + 气泡 + 「跳过」的通用层 `SpotlightTourOverlay`，输入一个 `SpotlightTourStep`；
  `SpotlightAnchorKey` 与 `spotlightTarget(_:isActive:)` 修饰符供页面登记目标。
- `BrowseCraft/Features/Startup/OnboardingTour.swift`：`OnboardingGuide`（版本号、判定、启动参数）、`OnboardingTourStore`（`@Observable`，当前阶段、两个已看标记、埋点）、各步文案、小标题与图标的拼装。
- `BrowseCraft/App/RootView.swift`：`TabView` 上叠引导层；开屏结束落到来源页且该弹时起欢迎卡；添加来源后切到库时登记库页那一步；设置页回看回调。
- `BrowseCraft/Features/Sources/SourcesView.swift`：空状态块、两张入口卡、「正在使用」卡、右上胶囊各挂一个目标；入口卡与胶囊的动作里告知引导。
- `BrowseCraft/Features/Library/Video/List/VideoContentGridView.swift`、`BrowseCraft/Features/Library/Components/LibraryContentView.swift`：三种网格的第一张卡挂目标。
- `BrowseCraft/Features/Settings/SettingsView.swift`：「关于」组首行。
- `BrowseCraft/Shared/Diagnostics/AppAnalytics.swift`、`AppAnalytics+Session.swift`、`AnalyticsValues.swift`：事件与两个枚举。
- `BrowseCraft/Features/Sources/Catalog/CatalogStyle.swift`：`tourScrim`、`tourAccent`、`tourGlowOpacity`、`tourBubbleShadow`、`tourButtonFill`、`tourOnButton`、`tourPrimaryShadow`（第八节）。
- 各语言 `Localizable.strings`；资产 `SettingsOnboarding.imageset` 与 `scripts/bundled-image-asset-budgets.txt`。

## 十一、验收清单

- 新文件要先跑 XcodeGen（`./scripts/regenerate-project.sh`）再 build。
- 模拟器用 `-BrowseCraftShowOnboarding`（可与演示模式同用）：欢迎卡 → 三步挖空位置对得上空状态块、底栏、两张卡；第 3 步只有两张卡能点，点了蒙层收起、sheet 照常弹出；
  三步的气泡步号行右侧都有「跳过」；浅色与深色各看一遍，深色下挖空的渐变描边与外发光看得出、气泡按钮反色、欢迎卡上半段仍是墨青色块；
  第 3 步青绿外环在呼吸，减弱动态效果打开时静止。
- 空库首装（不带演示模式）：开屏「跳过」后立即出欢迎卡；添加第一个来源切到库后出库页那一步；再冷启动不再出现。
- 已有来源时从设置页回看：第 1 步落在「正在使用」卡、第 3 步落在右上胶囊；若 List 里的目标矩形没有登记上来，气泡停在屏幕下方且无挖空，不卡住。
- 减弱动态效果打开时换步不做动画。
