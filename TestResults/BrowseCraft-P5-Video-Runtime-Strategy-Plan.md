# BrowseCraft P5 Video Runtime Strategy 中文详细计划

- 日期：2026-07-06
- 主题：在当前 `SourceRuntime` 架构下整理视频 runtime 的适配器边界。
- 当前前置状态：
  - 漫画已通过 `RuleSourceRuntime` + `SiteRule` 跑通。
  - RSS 已通过 `RSSSourceRuntime` + `RSSSourceDefinition` 跑通。
  - 视频已通过 `VideoSourceRuntime` + `MacCMSVideoHTMLMapper` 跑通 MacCMS 常见静态 HTML。
  - 插件已有 `SourceRuntimeKind.plugin`、`PluginSourceDefinition` 和 resolver 插槽，但未执行插件代码。

## 一句话目标

把当前“video 等于 MacCMS”的模型，整理为：

```text
SourceRuntimeKind.video
  VideoSourceRuntime
    Detection:
      VideoSourceDetection
        VideoAdapter.macCMS / genericHTML / iframe / plugin
        VideoRenderMode.staticHTML / webViewRequired
        VideoPlaybackMode.directMedia / iframe / unresolved
    Mapping:
      MacCMSVideoHTMLMapper / GenericHTMLVideoHTMLMapper
    Filtering:
      VideoHTMLNoiseFilter
    Rendering:
      StaticVideoHTMLProvider / WebViewVideoHTMLProvider
    Playback:
      DirectMediaPlaybackResolver / IframePlaybackResolver
```

其中：

- `VideoAdapter` 回答“列表/详情/基础资料怎么抽”。其中当前 `VideoAdapter.iframe` 语义是“内容资料层由 frame/iframe/embed 包住”，不是播放层 iframe。
- `Filtering` 回答“哪些 DOM 节点是广告、弹窗、跳转、无意义模块，应该过滤”。
- `VideoRenderMode` 回答“页面 HTML/DOM 怎么拿”。
- `VideoPlaybackMode` 回答“视频怎么播放”。
- MacCMS 是第一个内置视频适配器，不是顶层 source kind。
- 账号、验证码、签名、加密和特殊私有流程进入 plugin，不继续膨胀内置适配器。

核心产品原则：

```text
BrowseCraft 不是复刻原网站，而是抽出有意义的内容。
广告、弹窗、跳转、外链诱导、统计 iframe 和无意义模块必须在内容抽取阶段被过滤。
站点类型检测的评分和广告噪音过滤的评分必须分开。
```

## 当前架构判断

当前项目的核心边界是对的：

```text
SourceConfiguration
  .comic -> RuleSourceRuntime
  .rss   -> RSSSourceRuntime
  .video -> VideoSourceRuntime
  .plugin -> PluginSourceRuntime 后续
```

现有代码位置：

```text
BrowseCraftCore/Sources/BrowseCraftCore/Source/VideoSourceDefinitionModels.swift
BrowseCraft/Application/Runtime/Video/VideoSourceRuntime.swift
BrowseCraft/Application/Runtime/Video/Mapping/VideoHTMLMapper.swift
BrowseCraft/Application/Runtime/Video/Mapping/MacCMSVideoHTMLMapper.swift
BrowseCraft/Application/Runtime/Video/Loading/
BrowseCraft/Application/UseCases/Source/AddVideoSourceUseCase.swift
```

需要整理的是视频内部命名，而不是重做 `SourceRuntime` 架构。

## P5.1.1 更新 Runtime 文档

状态：已完成。

目标：让 `Application/Runtime/README.md` 和当前代码、后续计划一致。

已更新内容：

- `VideoSourceRuntime` 是视频 runtime。
- `VideoHTMLMapper` 是视频模板映射协议。
- `MacCMSVideoHTMLMapper` 是 `adapter/macCMS` 下的第一个内置 mapper。
- `VideoPlaybackRuntimeCapability` 是播放能力边界，后续 plugin 也可实现。
- RSS、Video、Plugin 都不扩展 `SiteRule`。
- 复杂账号/签名/加密站点进入 plugin。

验收：

```text
README 能解释 comic/rss/video/plugin 的 runtime 边界。
```

## P5.1.2 VideoAdapterDetector MVP

状态：MVP 已实现，未运行测试/build。

目标：先建立“输入视频站 URL/HTML 后判断应该使用哪个 `VideoAdapter`”的能力。

新增：

```text
BrowseCraft/Application/Runtime/Video/Mapping/VideoAdapterDetector.swift
```

核心模型：

```swift
enum VideoAdapter: String, Codable, Hashable {
    case macCMS
    case genericHTML
    case iframe
    case webView
    case plugin
}

struct VideoAdapterDetectionInput {
    var url: URL
    var html: String?
    var headers: [String: String]
}

struct VideoAdapterDetection {
    var adapter: VideoAdapter
    var confidence: Double
    var reasons: [String]
    var warnings: [String]
}

protocol VideoAdapterDetecting {
    func detect(_ input: VideoAdapterDetectionInput) -> VideoAdapterDetection
}
```

MVP 判断范围：

- `macCMS`：URL/HTML 命中 `/vodtype/`、`/vodshow/`、`/voddetail/`、`/vodplay/`、`player_aaaa`、`vod_name` 等特征。
- `genericHTML`：普通 HTML 里出现 `.m3u8`、`.mp4`、`video/source`、播放列表、剧集等泛视频信号。
- `iframe`：HTML 里出现 iframe 播放或 embed 结构。
- `webView`：HTML 像 JS shell、SPA 或缺少静态视频数据。
- `plugin`：验证码、登录、会员墙、签名、加密、混淆等复杂信号。

验收：

```text
VideoAdapterDetector 可以在不保存 Source、不加载 mapper 的前提下返回 adapter/confidence/reasons/warnings。
MacCMS URL 或 HTML 优先识别为 macCMS。
未知或弱信号默认返回 genericHTML 低置信度，并带 warning。
```

## P5.1.3 视频模型命名整理

状态：已实现，并通过 P5.1.7 定向测试。

目标：把 `VideoSourceSiteKind.macCMS` 改成一层适配器模型。

当前：

```swift
public struct VideoSourceDefinition {
    public var siteKind: VideoSourceSiteKind
    public var entryURL: URL
    public var seedURL: URL?
    public var entryKind: VideoSourceEntryKind
    public var routePatterns: VideoSourceRoutePatterns
    public var playbackPolicy: VideoPlaybackPolicy
    public var requiresAccount: Bool
    public var seedVodID: String?
    public var seedSourceIndex: Int?
    public var seedEpisodeIndex: Int?
    public var seedDetailURL: URL?
    public var seedPlayURL: URL?
}

public enum VideoSourceSiteKind {
    case macCMS
}
```

目标：

```swift
public struct VideoSourceDefinition: Codable, Hashable, Sendable {
    public var adapter: VideoAdapter
    public var entryURL: URL
    public var seedURL: URL?
    public var entryKind: VideoSourceEntryKind
    public var routePatterns: VideoSourceRoutePatterns?
    public var playbackPolicy: VideoPlaybackPolicy
    public var requiresAccount: Bool
    public var seedVodID: String?
    public var seedSourceIndex: Int?
    public var seedEpisodeIndex: Int?
    public var seedDetailURL: URL?
    public var seedPlayURL: URL?
}
```

新增：

```swift
public enum VideoAdapter: String, Codable, Hashable, Sendable {
    case macCMS
    case genericHTML
    case iframe
    case webView
    case plugin
}
```

兼容规则：

- 旧数据 `siteKind = macCMS` 解码为：
  ```text
  adapter = macCMS
  routePatterns = macCMS
  ```
- 新数据编码使用 `adapter`。
- `routePatterns` 改为可选，方便 `webView` / `plugin` 不依赖 MacCMS 路由模板。

涉及文件：

```text
BrowseCraft/Domain/Models/Source/SourceConfiguration.swift
BrowseCraft/Application/UseCases/Source/AddVideoSourceUseCase.swift
BrowseCraft/Domain/Models/Source/BuiltInSource.swift
BrowseCraftTests/Application/Video/VideoRuntimeMacCMSMappingTests.swift
BrowseCraftTests/Application/SourceRuntimeMappingTests.swift
```

验收：

```text
旧 MacCMS source 能解码。
新建视频 source 保存为 adapter=macCMS。
MacCMS runtime 行为不变。
```

## P5.1.4 VideoAdapterRegistry

状态：已实现，并通过 P5.1.7 定向测试。

目标：把视频 mapper 选择从 `SourceRuntimeFactory` 中抽离。

当前：

```swift
private func makeVideoHTMLMapper(definition: SourceDefinition) -> any VideoHTMLMapper {
    switch definition.video?.siteKind {
    case .macCMS, nil:
        return MacCMSVideoHTMLMapper()
    }
}
```

目标：

```swift
struct VideoAdapterRegistry {
    func mapper(for definition: SourceDefinition) -> any VideoHTMLMapper {
        switch definition.video?.adapter {
        case .macCMS, nil:
            return MacCMSVideoHTMLMapper()
        case .genericHTML:
            return GenericHTMLVideoHTMLMapper()
        case .iframe:
            return IframeEmbedVideoHTMLMapper()
        case .webView, .plugin:
            return UnsupportedVideoHTMLMapper()
        }
    }
}
```

第一步可以只真实接：

```swift
case .macCMS, nil:
    return MacCMSVideoHTMLMapper()
```

`genericHTML`、`iframe`、`webView` 和 `plugin` 可以先返回 unsupported，等后续节点实现。
`genericHTML` 已在 P5.1.7 接到 `GenericHTMLVideoHTMLMapper`。

涉及文件：

```text
BrowseCraft/Application/Runtime/SourceRuntimeFactory.swift
BrowseCraft/Application/Runtime/Video/Mapping/VideoAdapterRegistry.swift
```

验收：

```text
SourceRuntimeFactory 不直接知道每个视频模板 mapper。
视频适配器选择集中在 VideoAdapterRegistry。
```

## P5.1.5 MacCMS 作为 adapter/macCMS 稳定化

状态：已实现，并通过定向测试。

目标：保持当前 MacCMS 能力，同时明确它的边界。

MacCMS 覆盖范围：

```text
/vodtype/{id}.html
/vodshow/...
/voddetail/{id}.html
/vodplay/{vodID}-{sourceIndex}-{episodeIndex}.html
player_aaaa
ewave / stui / myui / module-item 等 MacCMS 皮肤 selector fallback
```

不拆为独立模板：

```text
ewave
stui
myui
module-item
```

这些只是 `MacCMSVideoHTMLMapper` 内部 fallback。

需要补齐的失败语义：

- RSS URL：提示从 RSS 添加。
- unsupported route：不是当前 MacCMS 支持路径。
- empty playback：播放脚本存在但没有 URL。
- requiresLogin：需要登录。
- vipOnly：VIP/会员限制。
- pageOnly：只有播放页，没有可用媒体直链。

验收：

```text
VideoRuntimeMacCMSMappingTests 继续通过。
MacCMS 的错误/限制状态可被 UI 或日志解释。
```

验证记录：

```text
TestResults/BrowseCraft-P5-1-5-MacCMS-Adapter-Stabilization-Run1.md
```

## P5.1.6 VideoPlaybackRuntimeCapability 正式化

状态：已实现，并通过 P5.1.7 定向测试；追加接入 GenericHTML video.home tab。

目标：把视频播放能力固定为 runtime capability，而不是只认 `VideoSourceRuntime`。

当前已有：

```text
BrowseCraft/Application/Runtime/Video/VideoPlaybackRuntimeCapability.swift
VideoSourceRuntime.loadPlayback(...)
```

目标：

```swift
protocol VideoPlaybackRuntimeCapability {
    func loadPlayback(_ input: SourceVideoPlaybackInput) async throws -> SourceVideoPlaybackOutput
    func loadVideoDetailContent(_ input: SourceDetailInput) async throws -> VideoDetailContent
}
```

规则：

- `VideoSourceRuntime` 实现它。
- 未来 `PluginSourceRuntime` 也可以实现它。
- 播放 UI / ViewModel 通过 `runtime as? VideoPlaybackRuntimeCapability` 调用。
- 不支持播放的 runtime 返回 unsupported。

验收：

```text
播放入口不依赖具体 VideoSourceRuntime 类型。
Plugin 视频后续可复用同一播放入口。
```

验证记录：

```text
TestResults/BrowseCraft-P5-1-6-VideoPlaybackRuntimeCapability-Run1.md
```

## P5.1.7 GenericHTMLVideoHTMLMapper

状态：已实现；视频列表 tab 已改为配置驱动。本次追加改造未运行测试/build。

目标：给 `VideoAdapter.genericHTML` 增加第二套内置适配器。

新增：

```text
BrowseCraft/Application/Runtime/Video/Mapping/GenericHTMLVideoHTMLMapper.swift
BrowseCraft/Application/Runtime/Video/Loading/VideoSourceListLoader.swift
BrowseCraft/Application/UseCases/Library/ResolveLibrarySourcePresentationUseCase.swift
BrowseCraft/Application/UseCases/Source/AddVideoSourceUseCase.swift
BrowseCraft/Application/UseCases/Source/RefreshSourceRuntimeUseCase.swift
BrowseCraft/Domain/Models/Source/BuiltInSource.swift
BrowseCraft/Domain/Models/Source/SourceConfiguration.swift
BrowseCraftTests/Application/Video/VideoRuntimeGenericHTMLMappingTests.swift
BrowseCraftTests/Fixtures/Video/GenericHTML/xvideos-home.html
BrowseCraftTests/Fixtures/Video/GenericHTML/xvideos-detail.html
```

能力范围：

```text
mapList:
  - 重复 card/list item
  - 按站点特征分组优先匹配，避免宽泛 selector 混入非条目节点
  - a[href] -> detailURL
  - img src/data-src -> cover
  - title/alt/text -> title

source list:
  - VideoSourceConfiguration.listTabs 持久化视频列表入口
  - BuiltInSource.allBuiltIns() 增加 GenericHTML 视频测试源，并在配置中写入最小首页 tab
  - GenericHTML 的更多 tab 应来自后续检测/用户配置，不在 BuiltInSource 中固定数量
  - MacCMS 内置源的分类 tab 从配置读取，不再由 ResolveLibrarySourcePresentationUseCase 固定生成
  - ResolveLibrarySourcePresentationUseCase 只负责把配置 tab 映射成 Library 横向 tab
  - RefreshSourceRuntimeUseCase 将选中 tab URL 写入 requestOverride
  - VideoSourceListLoader 读取 requestOverride URL，不再按 video.category.* 拼 /vodtype/{id}.html

mapDetail:
  - 按 video/genericHTML adapter 语义作为单视频详情页处理
  - 当前 detailURL 生成一个 VideoEpisode
  - 不扫描推荐/导航链接作为剧集

mapPlayback:
  - video/source[src]
  - .m3u8/.mp4
  - script 中 URL
  - html5player.setVideoHLS / setVideoUrlHigh / setVideoUrlLow
  - JSON-LD contentUrl
  - iframe[src] -> pageOnly/external embed
```

不处理：

```text
登录
验证码
JS 签名
加密解密
复杂 SPA
```

验收：

```text
adapter/genericHTML 能用本地 HTML fixtures 抽 list/detail/playback。
```

验证记录：

```text
TestResults/BrowseCraft-P5-1-7-GenericHTMLVideoHTMLMapper-Run1.md
```

## P5.1.8 VideoTabDiscovery

状态：已实现第一版。

目标：把视频源列表 tab 从手写默认值改成“发现/配置驱动”，做到 Library 横向 tab 真正按 `VideoSourceConfiguration.listTabs` 有多少显示多少。

定位：

```text
VideoTabDiscovery 不是 GenericHTML 独有能力。
它是 SourceRuntimeKind.video 的通用列表入口发现能力。
不同 VideoAdapter 提供不同 discoverer。
```

已新增：

```text
BrowseCraft/Application/Runtime/Video/Discovery/VideoTabDiscoverer.swift
BrowseCraft/Application/Runtime/Video/Discovery/VideoTabDiscovererRegistry.swift
BrowseCraft/Application/Runtime/Video/Discovery/MacCMSVideoTabDiscoverer.swift
BrowseCraft/Application/Runtime/Video/Discovery/GenericHTMLVideoTabDiscoverer.swift
BrowseCraftTests/Application/Video/VideoTabDiscoveryTests.swift
```

核心模型：

```swift
protocol VideoTabDiscovering {
    func discoverTabs(
        html: String,
        definition: VideoSourceDefinition,
        pageURL: URL
    ) throws -> [VideoSourceListTab]
}

struct VideoTabDiscovererRegistry {
    func discoverer(for adapter: VideoAdapter?) -> any VideoTabDiscovering
}
```

通用规则：

```text
输入：entryURL HTML + VideoSourceDefinition.adapter
输出：[VideoSourceListTab]
保存位置：Source.configuration.video.listTabs
展示：ResolveLibrarySourcePresentationUseCase 只映射配置，不生成固定 tab
加载：RefreshSourceRuntimeUseCase 将选中 tab.url 写入 requestOverride
```

MacCMS 发现策略：

```text
优先从导航/分类链接提取：
  - /vodtype/{id}.html
  - /vodshow/...
  - 文本标题来自链接 text/title

如果没有发现任何分类：
  - 只返回 entryURL 对应的 首页 tab
  - 不再默认塞 电影/电视剧/综艺/动漫 这 4 个固定分类
```

GenericHTML 发现策略：

```text
优先从主导航和分类区提取：
  - nav/menu/header 中的内部链接
  - category/tag/channel/list 类链接
  - 链接目标需要能被当前 GenericHTMLVideoHTMLMapper.mapList 解析出视频 item

MVP 可以先做静态过滤：
  - 同域或相对 URL
  - 排除 login/account/history/favorite/upload 等个人入口
  - 排除外部广告/直播/跳转
  - 去重并限制数量，保持顺序

如果没有发现任何可信列表入口：
  - 只返回 entryURL 对应的 首页 tab
```

WebView / Plugin 策略：

```text
webView:
  - 静态 HTML 无法可靠发现时返回首页 tab + warning
  - 后续由渲染 DOM discovery 补齐

plugin:
  - 由插件返回 tabs
  - App 内置 discoverer 不处理账号/验证码/签名流程
```

AddVideoSourceUseCase 接入：

```text
用户选择“视频”
  -> 上层如果已经抓取 entryURL HTML
  -> execute(entryURLString:name:entryHTML:headers:) 接收 HTML
  -> VideoAdapterDetector 判断 adapter
  -> VideoTabDiscovererRegistry 发现 tabs
  -> 保存 VideoSourceConfiguration(definition, listTabs)

当前 AddVideoSourceUseCase 不主动联网抓页面；没有 entryHTML 时只保底首页 tab。
```

验收：

```text
MacCMS 不再固定显示 5 个 tab。
GenericHTML 不再固定显示 1 个 tab。
Library tab 数量等于 source.configuration.video.listTabs.count。
无法发现分类时只保底首页 tab。
tab discovery 不影响 VideoHTMLMapper 的 list/detail/playback 职责。
```

本阶段实现文件：

```text
BrowseCraft/Application/Runtime/Video/Discovery/VideoTabDiscoverer.swift
BrowseCraft/Application/Runtime/Video/Discovery/VideoTabDiscovererRegistry.swift
BrowseCraft/Application/Runtime/Video/Discovery/MacCMSVideoTabDiscoverer.swift
BrowseCraft/Application/Runtime/Video/Discovery/GenericHTMLVideoTabDiscoverer.swift
BrowseCraft/Application/UseCases/Source/AddVideoSourceUseCase.swift
BrowseCraftTests/Application/Video/VideoTabDiscoveryTests.swift
```

剩余后续：

```text
AddVideoSource UI/流程层需要在保存视频源前抓取 entryURL HTML，并把 HTML 传给 AddVideoSourceUseCase。
内置测试源如果要动态发现 tab，也需要单独的内置源刷新/迁移流程，不能在 BuiltInSource 静态声明里硬编码分类。
```

## P5.1.9 VideoSourceDetection 三层模型

状态：已实现第一版。

目标：修正视频站检测模型，把视频网站按内容资料层、页面获取层、播放层拆开，避免 `genericHTML`、`iframe`、`webView` 抢同一个主类型。

核心结论：

```text
视频网站 runtime 大致分三层：

1. 内容资料层
   - 列表、分类、详情、标题、封面、简介、剧集
   - 对应 VideoAdapter

2. 页面获取层
   - HTML/DOM 怎么拿
   - 对应 VideoRenderMode

3. 播放层
   - 视频怎么播放
   - 对应 VideoPlaybackMode
```

物理结构：

```text
BrowseCraft/Application/Runtime/Video/
  Detection/
    VideoSourceDetection.swift
    VideoSourceDetector.swift

  Mapping/
    VideoAdapterRegistry.swift
    MacCMSVideoHTMLMapper.swift
    GenericHTMLVideoHTMLMapper.swift

  Filtering/
    VideoContentNoiseFilter.swift
    VideoHTMLNoiseFilter.swift
    VideoNoiseSignal.swift

  Rendering/
    VideoRenderMode.swift
    VideoHTMLProvider.swift
    StaticVideoHTMLProvider.swift
    WebViewVideoHTMLProvider.swift

  Playback/
    VideoPlaybackMode.swift
    VideoPlaybackResolver.swift
    DirectMediaPlaybackResolver.swift
    IframePlaybackResolver.swift

  Discovery/
    VideoTabDiscoverer.swift
    ...
```

本阶段已新增/调整：

```text
BrowseCraft/Application/Runtime/Video/Detection/VideoSourceDetection.swift
BrowseCraft/Application/Runtime/Video/Detection/VideoSourceDetector.swift
BrowseCraft/Application/Runtime/Video/Mapping/VideoAdapterDetector.swift
BrowseCraftTests/Application/Video/VideoSourceDetectionTests.swift
TestResults/BrowseCraft-P5-1-9-VideoSourceDetection-Run1.md
```

兼容策略：

```text
VideoAdapterDetector 暂时保留为旧 API 包装。
内部委托 VideoSourceDetector。
AddVideoSourceUseCase 当前仍消费 adapter。
renderMode/playbackMode 先进入检测结果和测试，为 P5.1.10/P5.1.11/P5.1.12 铺路。
```

检测输出建议：

```swift
struct VideoSourceDetection {
    var adapter: VideoAdapter
    var renderMode: VideoRenderMode
    var playbackMode: VideoPlaybackMode
    var confidence: Double
    var reasons: [String]
    var warnings: [String]
}

enum VideoAdapter {
    case macCMS
    case genericHTML
    case iframe
    case plugin
}

enum VideoRenderMode {
    case staticHTML
    case webViewRequired
}

enum VideoPlaybackMode {
    case directMedia
    case iframe
    case unresolved
}
```

检测顺序建议：

```text
1. 内容资料层：决定 VideoAdapter
   MacCMS 强模板信号：
   - /vodtype/
   - /vodshow/
   - /voddetail/
   - /vodplay/
   - player_aaaa / mac_player / mac_url

   GenericHTML 静态资料信号：
   - <video> / <source> / .m3u8 / .mp4 是强信号
   - 多个 /video /watch /play 链接是中信号
   - duration/views/thumbnail/card 是中信号
   - data-src/lazyload/playlist/episode/播放 只能作为弱信号

   Frame 内容资料信号：
   - frameset/frame 包住主要内容
   - iframe/embed 不是播放入口，而是列表/详情内容入口

   Plugin 信号：
   - 验证码/签名/加密/混淆/复杂私有 API
   - 单纯登录/VIP/会员/付费提示只进入 warnings，不强制 plugin

2. 页面获取层：决定 VideoRenderMode
   - staticHTML：入口 HTML 已有可抽资料
   - webViewRequired：HTML 是空 shell、SPA、必须 JS 渲染

3. 播放层：决定 VideoPlaybackMode
   - directMedia：可直接得到 mp4/m3u8
   - iframe：播放入口是 iframe/embed
   - unresolved：入口页阶段还不能确定

Iframe 播放信号：
   - <iframe>
   - embed/player 第三方地址
```

评分规则：

```text
不要“命中任意 marker 就判断成功”。
强信号可单独成立。
中信号需要组合。
弱信号只能辅助，不能单独决定 adapter。
低于阈值时 fallback genericHTML 或提示 unknown/plugin。
```

检测与过滤的边界：

```text
VideoSourceDetection 的 score 只判断：
  - adapter
  - renderMode
  - playbackMode

VideoSourceDetection 不判断某个 DOM 节点是不是广告。
广告、弹窗、跳转和无意义模块属于 Filtering 层。

同一个信号在不同层含义不同：
  - iframe 在 Detection 里可能代表播放模式
  - iframe 在 Filtering 里也可能是广告/统计/外链诱导
```

验收：

```text
GenericHTML 不会因为 data-src/lazyload 单点命中而误判。
iframe 播放站可以是 genericHTML + staticHTML + iframe。
WebView 站可以是 genericHTML + webViewRequired + unresolved，或 plugin + webViewRequired + unresolved。
MacCMS 站族识别仍保持高优先级。
VideoAdapterRegistry 只按 adapter 选择列表/详情 mapper。
Rendering 层只按 renderMode 决定 HTML/DOM 获取方式。
Playback 层只按 playbackMode 决定播放入口解析方式。
```

## P5.1.10 VideoSourceDetection 命名与 Plugin 判断修正

状态：待实现。

目标：在进入播放层和 WebView 层前，先把检测模型的命名和 plugin 判断收口，避免后续实现建立在含混语义上。

需要明确的三层命名：

```text
内容资料层：
  VideoAdapter.macCMS
  VideoAdapter.genericHTML
  VideoAdapter.iframe  当前兼容命名，语义是 frame 内容适配器
  VideoAdapter.plugin

页面获取层：
  VideoRenderMode.staticHTML
  VideoRenderMode.webViewRequired

播放层：
  VideoPlaybackMode.directMedia
  VideoPlaybackMode.iframe
  VideoPlaybackMode.unresolved
```

命名规则：

```text
frame = 内容资料层。
  站点的列表、详情或内容入口被 frame/iframe/embed 包住。
  当前 Core/App 已有 VideoAdapter.iframe 时，短期继续兼容使用，但文档和代码注释要写清楚它是 frame content adapter。

iframe = 播放层。
  最终播放入口是 iframe/embed/player。
  只对应 VideoPlaybackMode.iframe。
```

Plugin 判断规则：

```text
强 plugin 信号才进入 VideoAdapter.plugin：
  - captcha / 验证码
  - cryptojs / decrypt / encrypted
  - eval(function(p,a,c,k,e,d)) 或播放器脚本强混淆
  - sign/signature/动态 token 是核心请求必需参数
  - wasm 解密
  - 列表、详情或播放核心数据必须依赖账号 session / 私有 API

访问限制只进入 warnings，不强制 plugin：
  - login / 登录 / 请先登录 / 登录后
  - 会员 / VIP / 付费
  - 页面上存在会员区、登录按钮、VIP 文案
```

关键原则：

```text
有些网站不登录也能解析公开内容，只是页面上存在登录/VIP提示。
这种站点应该继续识别为 macCMS/genericHTML/frame，并带 warnings。

只有核心数据流必须依赖账号、验证码、签名、解密或私有流程时，才识别为 plugin。
```

检测与过滤边界：

```text
P5.1.10 不做广告过滤实现。
广告过滤仍放到后续 Filtering 层。
但 P5.1.10 要避免把广告 iframe 误判成内容 frame 或播放 iframe。
```

验收：

```text
登录/VIP 文案 + 可抽公开内容 => genericHTML/macCMS + warnings，不是 plugin。
验证码/加密/强混淆/核心签名流程 => plugin。
内容资料层 frame/frameset => VideoAdapter.iframe。
播放入口 iframe/embed => VideoPlaybackMode.iframe。
同一 HTML 同时有内容资料层和播放层信号时，检测结果能表达组合，而不是互相抢类型。
旧 VideoAdapterDetector 兼容 API 仍可返回 adapter/confidence/reasons/warnings。
```

## P5.1.11 Playback 层：IframePlayback 简单版

目标：处理普通 iframe 播放页，但不追多跳和解密。

新增：

```text
BrowseCraft/Application/Runtime/Video/Playback/IframePlaybackResolver.swift
```

能力：

```text
playback:
  - 提取 iframe[src]
  - 返回 pageOnly 或 externalEmbed 状态
```

不处理：

```text
iframe 多跳
iframe 内 JS 解密
第三方播放器绕过
```

验收：

```text
iframe 播放页不会被误判成失败，而是通过 VideoPlaybackMode.iframe 产生明确状态。
```

## P5.1.12 Rendering 层：WebViewRequired 预留

目标：模型上承认必须 WebView 的视频站，不污染普通 HTML 适配器。

语义：

```text
VideoRenderMode.webViewRequired = 不使用 WebView 就无法稳定解析。
```

典型情况：

- 初始 HTML 没有列表，必须 JS 渲染。
- 播放地址由 JS 运行后生成。
- 媒体地址只出现在 WebView network 请求里。
- iframe 播放器必须浏览器环境初始化。

规则：

- `VideoRenderMode.webViewRequired`
- `VideoSourceRuntime.capabilities.requiresWebView = true`
- 如果 WebView 视频 loader 尚未接入，返回：
  ```text
  WebView video runtime is not connected yet.
  ```

验收：

```text
需要 WebView 的视频站有明确归宿。
```

## P5.1.13 PluginSourceRuntime 边界

目标：复杂站点走插件，不继续扩张内置适配器。

插件负责：

```text
账号密码
Cookie/session
验证码
JS 签名
加密播放地址
Token 刷新
特殊私有 API
复杂 WebView 自动化
```

现有基础：

```swift
SourceRuntimeKind.plugin
PluginSourceDefinition
PluginPermission
```

规则：

- `unknown` 不作为长期运行态保存。
- 检测失败或复杂站点时，提示需要插件。
- 密码/token 不进入 source JSON，后续走 Keychain。
- 插件未接入前返回：
  ```text
  Plugin source runtime is not connected yet.
  ```

验收：

```text
复杂视频站不会继续增加内置 `VideoAdapter`。
```

## P5.1.14 AddVideoSourceUseCase 整理

目标：符合“用户先选视频，系统只做视频内部判断”。

当前：

```swift
AddVideoSourceUseCase.execute(entryURLString:name:entryHTML:headers:)
  -> VideoSourceURLResolver
  -> 有 entryHTML 时 VideoAdapterDetector
  -> 没有 entryHTML 时 fallback 首页 tab
```

第一步：

```text
AddVideoSource UI/流程层抓取 entryURL HTML
把 HTML 和 headers 传入 AddVideoSourceUseCase
```

第二步：

```text
VideoAdapterDetector
  -> VideoSourceDetection
     - adapter：macCMS / genericHTML / iframe / plugin
     - renderMode：staticHTML / webViewRequired
     - playbackMode：directMedia / iframe / unresolved
```

第三步：

```text
VideoTabDiscovererRegistry
  -> discover tabs
  -> persist VideoSourceConfiguration.listTabs
```

不做：

- 不在视频 flow 里识别漫画。
- 不在视频 flow 里真正添加 RSS。
- RSS URL 只提示用户走 RSS 添加。

验收：

```text
用户大分类，系统小分类。
视频添加流程只负责视频内部适配器选择。
VideoSourceDetection 检测结果可用于预检 UI 展示。
```

## P5.1.15 Filtering 层：VideoContentNoiseFilter

目标：实现 BrowseCraft 视频源的核心产品能力之一：从网页里抽取有效内容时过滤广告、弹窗、跳转、无意义模块。

物理位置：

```text
BrowseCraft/Application/Runtime/Video/Filtering/VideoContentNoiseFilter.swift
BrowseCraft/Application/Runtime/Video/Filtering/VideoHTMLNoiseFilter.swift
BrowseCraft/Application/Runtime/Video/Filtering/VideoNoiseSignal.swift
```

职责：

```text
输入：
  - SwiftSoup Element candidate
  - pageURL
  - source definition / adapter context

输出：
  - keep / reject
  - reasons
  - confidence
```

强噪音信号：

```text
class/id 包含：
  ad / ads / advert / banner / popup / modal / sponsor / promo

链接/iframe 指向：
  外部广告域
  tracker/stat/click/jump
  download/app install
  客服/扫码/推广

交互行为：
  onclick window.open
  javascript:void
  target blank 且非内容详情页
```

弱噪音信号：

```text
没有 title
没有 detail link
没有 cover
没有 duration/latest/meta
尺寸/结构不像内容卡片
文本只包含广告/推广/下载/APP/扫码
```

保留信号：

```text
有稳定详情链接
有标题
有封面
有时长/集数/更新状态
链接同域或可解析为当前站内容 URL
iframe src 命中 player/embed/video 且处于播放上下文
```

接入点：

```text
GenericHTMLVideoHTMLMapper.mapList
  -> 选 candidate item
  -> VideoHTMLNoiseFilter 过滤
  -> 输出 SourceContentItem

MacCMSVideoHTMLMapper.mapList
  -> 可先保持轻量过滤，避免误伤模板站正常卡片
```

非目标：

```text
不在 VideoSourceDetection 里过滤广告。
不把广告过滤规则写成站点类型判断规则。
不做全局网页净化器；只服务内容候选节点和播放候选节点。
```

验收：

```text
GenericHTML 列表不会把广告卡片、弹窗入口、下载推广作为 SourceContentItem。
播放页不会把广告 iframe 当成主要播放入口。
真实内容 iframe/player 不被误过滤。
过滤结果带 reason，方便调试和后续 UI/日志展示。
```

## 推荐执行顺序

第一阶段：架构命名稳定

```text
P5.1.1 Runtime README
P5.1.2 VideoAdapterDetector MVP
P5.1.3 VideoSourceDefinition 命名整理
P5.1.4 VideoAdapterRegistry
P5.1.5 MacCMS 稳定化
P5.1.6 VideoPlaybackRuntimeCapability
```

第二阶段：内置适配器扩展

```text
P5.1.7 GenericHTMLVideoHTMLMapper
P5.1.8 VideoTabDiscovery
P5.1.9 VideoSourceDetection 三层模型
P5.1.10 VideoSourceDetection 命名与 Plugin 判断修正
```

第三阶段：复杂站点出口

```text
P5.1.11 Playback 层：IframePlayback
P5.1.12 Rendering 层：WebViewRequired
P5.1.13 PluginSourceRuntime
P5.1.14 AddVideoSourceUseCase 整理
P5.1.15 Filtering 层：VideoContentNoiseFilter
```

## 非目标

- 不把视频重新塞回 `SiteRule`。
- 不把 RSS 重新塞回 `SiteRule`。
- 不为 ewave/stui/myui/module-item 建独立顶层模板。
- 不在内置适配器里处理登录、验证码、复杂签名和解密。
- 不在本阶段执行插件代码。
- 不跑真实站点，不访问受限内容。
- 不把广告过滤混进站点类型检测；Filtering 层单独处理噪音节点。

## 当前建议

下一步优先做 P5.1.10。P5.1.9 已经把检测结果迁移为三层，但还需要把命名和 plugin 判断收口：

```text
VideoSourceDetection
  adapter      = macCMS / genericHTML / iframe / plugin
  renderMode   = staticHTML / webViewRequired
  playbackMode = directMedia / iframe / unresolved
```

P5.1.10 应该先修正：

```text
VideoAdapter.iframe 当前只表示内容资料层 frame adapter。
VideoPlaybackMode.iframe 才表示播放层 iframe。
登录/VIP/会员提示只作为 warnings。
验证码、签名、加密、混淆、核心私有 API 才进入 plugin。
```

完成 P5.1.10 后，再进入 P5.1.11 的 `Playback` 层 iframe 处理，让 `VideoPlaybackMode.iframe` 有明确执行路径。
