# BrowseCraft P5.1.9 VideoSourceDetection Run 1

日期：2026-07-07

## 目标

把视频源检测从单一 `VideoAdapter` 判断升级为三层检测模型：

```text
adapter      = 内容资料层，决定列表/详情基础资料怎么抽
renderMode   = 页面获取层，决定 HTML/DOM 怎么拿
playbackMode = 播放层，决定视频入口怎么播放
```

本阶段只改检测结构，不接 iframe 播放、不接 WebView loader、不实现广告过滤。

## 已完成

新增三层检测模型：

```text
BrowseCraft/Application/Runtime/Video/Detection/VideoSourceDetection.swift
BrowseCraft/Application/Runtime/Video/Detection/VideoSourceDetector.swift
```

核心模型：

```text
VideoSourceDetection
  adapter: VideoAdapter
  renderMode: VideoRenderMode
  playbackMode: VideoPlaybackMode
  confidence
  reasons
  warnings

VideoRenderMode
  staticHTML
  webViewRequired

VideoPlaybackMode
  directMedia
  iframe
  unresolved
```

兼容旧入口：

```text
BrowseCraft/Application/Runtime/Video/Mapping/VideoAdapterDetector.swift
```

`VideoAdapterDetector` 现在是兼容包装，内部调用 `VideoSourceDetector`，继续返回旧的 `VideoAdapterDetection`，避免现有 `AddVideoSourceUseCase` 和测试一次性大改。

## 检测规则

MacCMS：

- `/vodtype/`、`/vodshow/`、`/voddetail/`、`/vodplay/` 是强信号。
- `player_aaaa`、`mac_player`、`mac_url` 是强信号。
- `vod_id`、`vod_name`、`zanpian` 只作为弱信号组合。

GenericHTML：

- `<video>`、`<source>`、`.m3u8`、`.mp4` 是强信号。
- 多个 `/video`、`/watch`、`/play` 链接是中信号。
- `video-card`、`duration`、`thumb` 等是中信号。
- `data-src`、`lazyload`、`playlist`、`episode`、`播放` 只作为弱信号，不能单独高置信判断。

Render：

- `id="app"`、`__nuxt`、`__next`、`data-reactroot`、空 shell 等判断为 `webViewRequired`。
- 否则默认 `staticHTML`。

Playback：

- `.m3u8`、`.mp4`、`<video>`、`<source>` 判断为 `directMedia`。
- `<iframe>`、`embed`、`player` 判断为 `iframe`。
- 入口页阶段不能确定时为 `unresolved`。

Plugin：

- CAPTCHA、登录后、会员专享、CryptoJS、decrypt、encrypted、packer eval 等强复杂信号会输出 `adapter: plugin`。

## 新增测试

```text
BrowseCraftTests/Application/Video/VideoSourceDetectionTests.swift
```

覆盖：

- MacCMS 路由检测。
- GenericHTML 直链媒体检测。
- 弱信号不会高置信误判。
- iframe 是 playback 层，不是 adapter 层。
- WebView 是 render 层，不是 adapter 层。
- 复杂限制信号走 plugin。
- 旧 `VideoAdapterDetector` 包装三层检测。

## 测试

用户要求“测试”后执行：

```text
xcodegen generate
env -u GEM_HOME -u GEM_PATH pod install
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceDetectionTests
```

结果：

```text
VideoSourceDetectionTests：7 tests passed
TEST SUCCEEDED
```

xcresult：

```text
/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-cmivihkzqbasvdgazoybpgpjhgvv/Logs/Test/Test-BrowseCraft-2026.07.07_07-34-29-+0900.xcresult
```

## 后续

- P5.1.10 接 `VideoPlaybackMode.iframe` 的播放层处理。
- P5.1.11 接 `VideoRenderMode.webViewRequired` 的渲染层处理。
- P5.1.14 单独实现广告/弹窗/无意义节点过滤，不混入 source detection score。
