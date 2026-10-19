# 品牌等待标记

设计稿（画布，含组件四种状态、删除账号进度遮罩现在 / 改后浅色 / 改后深色、iCloud 首次恢复卡现在 / 改后浅色 / 改后深色、冷启动三段现在与改后、即梦素材取景）：
[品牌等待标记设计稿](https://claude.ai/artifact/A2iVyGsDyxvV52p3cxF3xX)；设计文档：[品牌等待标记设计书](https://claude.ai/artifact/1DwD3tdtqiQpBR71zh3erR)。
设计与实施状态见 [STATUS.md](../STATUS.md)。宿主的合同：[删除账号](Account-Deletion-Design.md) 第四节进度遮罩、
[来源页](Sources-Page-Redesign-Design.md) 2.7 与 [收藏页](Favorites-Page-Redesign-Design.md) 的 iCloud 首次恢复卡。

## 一、背景

网络请求的等待都在原地处理：按钮内转圈加 `.disabled`、骨架、只锁局部、sheet 禁止下滑关闭。真正盖住全屏、吞掉点击的只有删除账号一处。
全屏 HUD 会推翻各页已定的加载态，还会挡住下拉刷新，而下拉是空态与失败态唯一的重试入口（`LibraryView` 的 `isInteractionLocked` 注释）。
所以不做通用的网络请求 HUD，只做一枚共用的等待标记，替换用户盯着等的几处系统转圈。

- `BCA-UI-007` App 不提供全局的网络请求 HUD，也不为等待新增吞掉点击的全屏遮罩；需要等待时沿用各页合同已定的原地做法。
  品牌等待标记 `BrandWaitingMark` 只替换第二节「放」列出的位置里的指示器，宿主的版式、文字、是否挡点击都不因它改变；
  它静音播放、不改音频会话，不得打断正在出声的音频（其他 App 的音乐、本 App 的播放）。

## 二、范围

| | 位置 |
| --- | --- |
| 放 | 删除账号进度遮罩（大号）；iCloud 首次恢复卡的「正在等待 iCloud」「正在从 iCloud 恢复」两态（中号），失败态不变 |
| 改但不放标记 | 冷启动的建库段：白底转圈换成 `LaunchSplash` 静图（第五节） |
| 不放 | 按钮内与行内的小转圈（不到 44pt，各页合同已定）、骨架、分页脚、WebView 进度条、有声书播放键内的单集加载、阅读器图片加载、内购页、网址输入页检查进度卡（等待很短，四步清单本身就是进度） |

同一屏只出现一枚标记；来源页与收藏页各有一张恢复卡，不会同屏。启动视频本身就是品牌加载动画（盖住来源检查与库加载、加载完才出「跳过」），保持不变。

## 三、组件

`BrandWaitingMark(size:)`：没有文字、不可点、`accessibilityHidden`，读屏只读宿主的文字。三层叠放：

1. 底板：圆形，`CatalogPalette.brandWaitingFill`，深浅色同值；浅色卡片上读作一枚深色块，与深色类型瓷砖同一种语言。
2. 海报帧：视频第一帧的静图，视频就绪前与开了「减弱动态效果」时显示。
3. 循环视频：就绪后 0.25 秒淡入。复用启动视频的 `StartupVideoPlayerView`（`AVQueuePlayer` + `AVPlayerLooper`），以 `isMuted: true` 播放：
   静音、不激活也不改 `AVAudioSession`；素材本身没有音轨。App 将要失去活跃时暂停在当前帧、重新活跃时续播，由播放器监听 `UIApplication` 的活跃通知完成，不靠宿主传入的 `scenePhase`：
   推入页（删除账号）回到前台时 `scenePhase` 不一定把视图刷新回 active，只靠它会一直停在暂停那一帧。视图消失即拆掉播放器与通知监听。

素材缺失或播放失败时退回同尺寸的系统 `ProgressView`（静止的海报帧看不出还在等），缺失只记 `debug` 日志，不加埋点。

## 四、素材

| 项 | 取值 |
| --- | --- |
| 视频 | `BrowseCraft/Resources/Waiting/brand-waiting.mp4`：288×288（96pt @3x）、HEVC（`hvc1`）、24 帧 / 秒、4 秒 96 帧循环、无音轨 |
| 海报帧 | 资产目录 `BrandWaitingPoster`：288×288 单档 PNG，按 `scripts/bundled-image-asset-budgets.txt` 登记（`BCA-BUILD-006`、`BCA-BUILD-007`） |
| 内容 | 看板娘 Q 版胸像，双手捧着发光的青色倒三角光标；呼吸、眨一次眼、光标浮动；纯色墨青底 |
| 来源 | 即梦图片生成出关键帧，视频生成「首尾帧」模式首尾都填同一张；成片去掉第 1 帧（输入图本身，亮度与后续帧不同）后循环，接缝最平 |

替换素材时沿用设计文档「素材规格」一节的提示词与后期命令，保持尺寸、无音轨与首尾帧做法；底板色随新素材圆边的实际背景色更新。
视频不在图片资产闸门的范围内，字节量以本节为准：不超过 300 KB。

## 五、各宿主

| 宿主 | 换掉 | 保留 |
| --- | --- | --- |
| 删除账号进度遮罩 `AccountDeletionView` | 大号系统转圈 → 96pt 标记 | `pressedScrim` 遮罩、250pt 卡片、两行文字、吞掉点击、隐藏返回 |
| iCloud 首次恢复卡 `CloudSyncInitialRestoreView` | 56pt 蓝色 iCloud 图标圈与底部小转圈 → 一枚 56pt 标记 | 标题、说明、圆角 22 卡片、不挡点击（宿主可关掉命中测试，下拉照常） |
| 冷启动建库段 `BrowseCraftApp` | 白底系统转圈 + 文字 → 黑底上铺满 `LaunchSplash`（与系统启动屏同一张、同样填满） | 建库流程；读屏仍读「正在打开 AnyPortal…」 |

## 六、其余状态

| 状态 | 表现 |
| --- | --- |
| 视频还没就绪 | 海报帧，就绪后淡入 |
| 开了「减弱动态效果」 | 只显示海报帧，不播视频；海报帧也缺时退回系统转圈 |
| 素材缺失或播放失败 | 同尺寸系统转圈 |
| App 在后台 | 暂停在当前帧，回前台续播 |
| 浅色 / 深色 | 同一套素材，底板深浅同值 |

## 七、视觉取值

尺寸两档：大号 96pt（删除账号）、中号 56pt（恢复卡）。底板色 `brandWaitingFill` 为 #0E1D25，取自素材圆边的实际背景色。不加阴影与描边。
启动建库段的黑底与启动屏、启动动画同属 `CatalogPalette` 注释登记的功能性取值。

## 八、裁定

2026-10-20 用户裁定待裁定八项全取 A：主题用看板娘 Q 版小动作；建库段换启动屏静图、启动视频不动；网址输入页不放；圆形墨青底；大 96 / 中 56 两档；
恢复卡去掉小转圈；素材用 MP4 循环；减弱动态效果显示海报帧。看画布后确认，素材由用户在即梦生成并确认。

## 九、实现位置

- `BrowseCraft/Features/Shared/BrandWaitingMark.swift`：组件、尺寸两档、资源与海报帧、回退。
- `BrowseCraft/Shared/Resources/BundledWaitingAnimationResource.swift`：视频地址查找（兼容扁平复制与保留 `Waiting` 子目录两种打包），海报帧名。
- `BrowseCraft/Features/Startup/StartupVideoPlayerView.swift`：`isMuted` 参数，静音时不碰音频会话；启动视频照旧带声音与 ambient 会话。
- `BrowseCraft/Features/Settings/AccountDeletion/AccountDeletionView.swift`、`BrowseCraft/Features/Shared/CloudSyncInitialRestoreView.swift`、`BrowseCraft/BrowseCraftApp.swift`：三处宿主。
- `BrowseCraft/Features/Sources/Catalog/CatalogStyle.swift`：`brandWaitingFill` 与功能性取值登记。
- 资源：`BrowseCraft/Resources/Waiting/brand-waiting.mp4`、`BrowseCraft/Assets.xcassets/BrandWaitingPoster.imageset`；预算声明 `scripts/bundled-image-asset-budgets.txt`。

## 十、验收清单

- 新文件要先跑 XcodeGen（`./scripts/regenerate-project.sh`）再 build；包内能找到 `brand-waiting.mp4` 与 `BrandWaitingPoster`。
- 删除账号：遮罩卡片里是 96pt 圆形标记在动，卡片不挤压文字；遮罩仍吞掉点击、不能返回；浅色与深色各看一次。
- iCloud 首次恢复：来源页与收藏页的恢复卡两态都是 56pt 标记、没有小转圈；卡片下方仍能下拉。
- 冷启动：系统启动屏 → 建库段 → 启动视频看起来是同一张图接着播放，中间没有白底闪一下；读屏念「正在打开 AnyPortal…」。
- 静音与音频会话：其他 App 放着音乐时进入删除账号遮罩或出现恢复卡，音乐不中断、不变小。
- 减弱动态效果打开时只有静图；App 进后台再回来，标记继续播放。
