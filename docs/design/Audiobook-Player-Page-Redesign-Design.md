# 有声书播放页的视觉与信息结构重设计

设计稿（画布，含播放中、暂停无封面、打开中、全部听完了、单集已失效、没加载出来、目录、倍速菜单、尺寸与取值，共 9 张）：
[有声书播放页重设计](https://claude.ai/artifact/D6tba2Bdyrvhib5gPHSi1T)；设计文档：[有声书播放页重设计](https://claude.ai/artifact/CLoksXiFNRAFvmhn85NNoS)。
设计与实施状态见 [STATUS.md](../STATUS.md)。入口是 [站点书详情页](Book-Detail-Page-Redesign-Design.md)、[库页书籍库](Library-Book-Page-Redesign-Design.md)
的「上次听到」瓷砖与历史页；播放内核与接线见 [读书 kind App 侧接线](Book-Kind-Wiring-Design.md) 第十六节。

## 一、背景

播放页是接线时从 Readium TestApp 的 `AudiobookReader` 照搬来的：系统导航栏标题（书名截断）+ 右上目录与书签、白底、1:1 封面、
只写集名、系统蓝 `Slider` 与五个同大小的系统蓝图标、没有倍速，与重做过的站点书详情页、书籍库断开。单集音频在站点上失效时一直转圈
（fwq `APP-MEMO-043`，2026-10-19 leting8 真机）；有声书一打开就按文字书「进一章 +50」记广告分，音频还没加载就可能弹广告（2026-10-20 用户发现）。

Readium 只给引擎：`AudioNavigator`（播放、拖动、换集、倍速、音频会话）、`NowPlayingInfo`；播放页、顶栏与 sheet 全是本项目的 SwiftUI，可以整页重做。

## 二、规则与引擎实际给什么数据

核对线上目录全部四条有声规则（Loyal Books、恋听网、一夜幻听网、乐听吧）、Core 运行期模型与 Readium 3.x：

| 数据 | 有没有 | 页面怎么用 |
| --- | --- | --- |
| 书名 | 四条都给 `fields.title` | 标题区第三行 |
| 封面 | 只有 Loyal Books 给 `fields.cover` | 有封面取色做背景；中文三站没有，用书籍深色色块 + 耳机 |
| 作者 / 播讲人 | 都不给，Core 也没有播讲人字段 | 不留位置 |
| 集列表 | `chapterRule` 的 `title` + `readerURL`，中文站常见上千集 | 目录 sheet、眉行总集数 |
| 当前集序号 | `readingOrder` 下标 | 眉行「第 N / M 集」（只有一集时不出） |
| 一集时长 | 规则有 `media.duration` / `mediaAPI.durationPath`，四条都不给；当前集开始加载后由 AVPlayer 报出 | 进度条只表示当前集；整本没有时长与进度 |
| 倍速 | 引擎支持 `AudioNavigator.submitPreferences(AudioPreferences(speed:))` | 倍速五档 |
| 单集失败 | `MediaPlaybackState` 没有 failed，`presentError` 不可用 | App 自己从音频请求判定（第六节） |

## 三、入口与范围

站点书详情页（开始 / 继续收听、点某一集）、书籍库「上次听到」瓷砖、历史页行都以 `navigationDestination` 推入；进入后隐藏底栏与系统导航栏，
返回与目录在页面里。离开本页即停播（不做后台续播与迷你播放条，裁定 10，记账另立项）。

不在本期：有声书书签（裁定 8 = C）、睡眠定时（裁定 7 = C）、本地导入的有声书、规则侧给时长或播讲人、问题报告入口（`BCA-UI-006` 只允许库页与三种详情页，
播放页的问题在站点书详情页用「某一集的内容」报）。

## 四、页面结构

整页一屏、不滚动。**整页固定沉浸深色**（裁定 1，用户看画布后改）：与影视播放器同属「播放器」功能性例外（`CatalogPalette` 注释登记），
只对本页局部设 `.environment(\.colorScheme, .dark)`，不用 `preferredColorScheme`（推入页上用它会把整个窗口连同下面的详情页一起变深）。
状态栏文字由系统按背后内容自动取白色（与影视详情深色头图同一做法）。

**封面取色的流动背景**（`AudiobookFlowingBackdrop`）：从封面取 3 个主色并压暗（`AudiobookBackdropPalette`），一个做底，三团柔边色块各自
16 / 19 / 22 秒往返漂移，底部加暗让字可读；没有封面用书籍青绿深调（底 #07120F，色块 #1E7D68 / #152A26 / #2F8F7A）。
性能约束：色块用径向渐变画成柔边，不做逐帧实时模糊；动画只改位移与缩放交给 Core Animation 合成；取色只在拿到封面时把封面缩到 24×24 做一次；
回到后台、开了「减弱动态效果」时停住。不播视频、不碰音频会话（内购页那种循环视频背景不采用）。

| 块 | 样子 |
| --- | --- |
| 顶栏 | 左返回、右目录：40pt 毛玻璃圆 + 白 16% 描边，热区 44（做法照 `DetailTopButtons`）；集列表为空时目录变淡禁用；不写书名 |
| 封面 | 正方形，边长 min(屏宽 − 96, 300)，矮屏再缩到保证倍速胶囊不出屏；圆角 18、深阴影；无封面为书籍深色色块 + 耳机（裁定 3） |
| 标题区 | 眉行 caption 粗体白 72%「第 N / M 集」，播放中前带三根跳动的波形；集名 title3 粗体两行（缺时写「第 N 集」）；书名 subheadline 白 68% 一行（裁定 4） |
| 进度条 | 自绘 `AudiobookProgressBar`：轨道 4pt 白 22%、已听白、滑块 14 / 按住 22、热区 44；拖动时左侧显示目标时刻、松手才跳；下方已听 · 本集总长，时长未知写「--:--」；读屏可调节：上滑 +30 秒、下滑 −10 秒 |
| 主控件 | −10 秒 · 上一集 · 72pt 白色实心播放键（图形取背景底色）· 下一集 · +30 秒（裁定 5）；首集「上一集」、末集「下一集」变淡禁用；加载中播放键圆内转圈 |
| 倍速 | 44 高毛玻璃胶囊，点开是系统菜单「播放速度」0.75 / 1.0 / 1.25 / 1.5 / 2.0×，全局记一个值（`AudiobookPlaybackSpeed`，存 UserDefaults，裁定 6）；不是 1.0× 时字变书籍青绿 |

## 五、目录

右上目录弹出 `AudiobookContentsSheet`（随播放页深色）：「关闭」左上，大标题「目录」+ 集数；卡片行组圆角 18、行高 52：序号 + 集名，
当前集青绿 16% 底 + 粗体 + 波形，打开时滚到当前集；超过 100 集顶部用分段芯片（`LibraryChipBar`，每 100 集一段）；本次打开里已失效的集标「已失效」。
点一行关 sheet、从那一集开头播。有声书不设书签（裁定 8 = C：续听位置已自动保存，书签只在本机、别处不显示）；文字书阅读页的书签不变。

## 六、其余状态（含 APP-MEMO-043）

| 状态 | 怎么判定 | 页面 |
| --- | --- | --- |
| 打开中 | 整本还在取；整站有声（reader 规则全 audio）时 | `AudiobookLoadingView`：深色流动背景上的同形骨架，只有返回可点；不是整站有声时照旧转圈 |
| 整本打不开 | 清单或目录取失败 | 库页「载入失败」插画 + 原因 + 下拉重试（`LibraryPlaceholderView`，两种阅读页共用） |
| 单集加载中 | `MediaPlaybackState.loading` | 播放键圆内转圈，进度条不可拖 |
| 单集在站点上已失效 | 音频请求 HTTP 404 / 403 / 410，或播放页型章节取到页面却解不出音频 | 进度条位置换成一行横条 `AudiobookFailureStrip`（毛玻璃 + 警示橙描边）「本集音频在站点上已失效」+ 白色「下一集 ›」；封面不缩、不自动跳（裁定 9）；末集没有「下一集」；播放键变灰 |
| 单集没加载出来 | 网络、超时、HTTP 5xx / 429 等 | 同一行横条「这一集没加载出来」+「重试」+「下一集 ›」 |
| 听完最后一集 | `shouldPlayNextResource` 在最后一集回调 | 眉行「全部听完了」，播放键回到播放 |
| 广告 | 只按实际播放计分（`.playing` 且时间前进，每 600 秒 +50，满 100 弹） | 打开时不再按章 +50；弹出方式不改 |

失效判定的链路：`SiteBookAudioHTTPClient` 在 `didFailWithError`（以及播放页取页失败的 `willStartRequest`）里按状态码分类为 `BookAudioResourceFailure`，
经出版物装配传入的回调报给 `BookReaderViewModel`，按出版物里登记的这一集地址（http / https 都认）对回集序号；取消（换 Range、换集）不算失败。
判定记一条 notice 日志 `audio-chapter-unavailable`（主机、路径、类别、状态码），不加新埋点，不进问题报告失败快照（裁定 11）。

## 七、视觉取值

除封面取色外不新增色值。前景取 `CatalogPalette` 新增的 `immersive*` 一组（主字白、次级白 68%、眉行白 72%、轨道白 22%、描边白 16%、背景底部压暗黑 45%）；
毛玻璃为系统 `ultraThinMaterial`（深色）；书籍青绿只用在倍速非 1.0× 与目录当前集；失败横条描边与图标取 `CatalogPalette.warning` 的深色档。
新做的组件只有流动背景、进度条与 72pt 播放键，补进设计索引「可复用组件」。

## 八、裁定

2026-10-20 用户裁定：第 1–6、9–11 项取 A，第 7、8 项取 C（不做睡眠定时、有声书去掉书签）；看画布后把第 1 项改为「沉浸深色 + 封面取色流动背景」
（要和内购页一样有动态，但不用视频），单集失败提示从状态卡改成一行横条（状态框太大、挡住封面）；广告计分修正随本页一起实施。

## 九、实现位置

- `BrowseCraft/Features/Library/Book/Reader/AudiobookPlayerView.swift`：播放页、`AudiobookLoadingView`、顶栏、主控件、眉行波形、`AudiobookProgressBar`、`AudiobookTimeFormatter`、`AudiobookFailureStrip`、倍速菜单。
- `AudiobookBackdrop.swift`：`AudiobookBackdropPalette`、`AudiobookCoverColor`（24×24 k-means 取色）、`AudiobookFlowingBackdrop`。
- `AudiobookContentsSheet.swift`：目录 sheet；`AudiobookPlaybackSpeed.swift`：倍速五档与记忆。
- `BookReaderView.swift`：有声书隐藏系统导航栏与工具栏按钮、打开中骨架、失败态下拉重试；文字书分支不变。
- `BookReaderViewModel.swift`：集序号与总集数、单集失败表、听完、倍速、上下集 / 重试 / 点集、锁屏封面、`reopen()`、`expectsAudiobook`；打开时按章计分只给文字书。
- `AudiobookRemoteControls.swift`：锁屏封面。
- `BrowseCraft/Application/UseCases/Book/BookAudioResourceFailure.swift`：失效值与状态码分类；`Infrastructure/Book/SiteBookAudioHTTPClient.swift`：判定与回调；
  `ReadiumSitePublicationBuilder.swift`、`BookReaderPublicationPorts.swift`、`App/Composition/ReadiumPublicationCompositionAdapters.swift`：回调接线。
- `Features/Sources/Catalog/CatalogStyle.swift`：`immersive*` 取值与功能性例外登记。
- 三份 `Localizable.strings`：`audiobook_player_*`、`audiobook_contents_*` 十九条。
- 测试：`BrowseCraftTests/Features/Book/AudiobookPlayerTests.swift`（失效分类、倍速记忆、取色）。

## 十、验收清单

- 模拟器：Loyal Books（有封面、取色）与中文有声站（无封面）各走一遍：播放 / 暂停、拖动、上下集、−10 / +30、倍速五档与重启后记忆、目录滚到当前集与点集、听完最后一集、深色背景在后台回来时停住与恢复。
- 单集失效：leting8 作品 20928 第 1 集（xmcdn 404）应出「本集音频在站点上已失效」横条、不转圈、「下一集」能播；断网时应出「没加载出来」+「重试」。
- 广告：有声书打开后立刻不弹广告；实际播放 600 秒记一次分。
- 真机：锁屏封面与倍速、耳机线控、Instruments Energy Log 看流动背景的耗电。
