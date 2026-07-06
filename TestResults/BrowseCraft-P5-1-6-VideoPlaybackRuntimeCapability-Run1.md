# BrowseCraft P5.1.6 VideoPlaybackRuntimeCapability - Run 1

- 日期：2026-07-06
- 范围：视频播放 runtime capability 命名收口
- 类型：代码实现记录

## 完成内容

- 将视频播放能力协议从 `VideoPlaybackRuntimeProviding` 重命名为 `VideoPlaybackRuntimeCapability`。
- 将文件重命名为：

```text
BrowseCraft/Application/Runtime/Video/VideoPlaybackRuntimeCapability.swift
```

- `VideoSourceRuntime` 继续实现视频播放能力协议。
- `VideoDetailViewModel` 和 `VideoPlayerViewModel` 的 runtime cast 改为：

```swift
runtime as? any VideoPlaybackRuntimeCapability
```

- Runtime README 和 P5 计划同步使用 capability 命名。

## 修改文件

```text
BrowseCraft/Application/Runtime/Video/VideoPlaybackRuntimeCapability.swift
BrowseCraft/Application/Runtime/Video/VideoPlaybackRuntimeProviding.swift
BrowseCraft/Features/Video/VideoDetailViewModel.swift
BrowseCraft/Features/Video/VideoPlayerViewModel.swift
BrowseCraft/Application/Runtime/README.md
TestResults/BrowseCraft-P5-Video-Runtime-Strategy-Plan.md
```

## 验证

未运行测试/build。

原因：本次用户要求开始实装，但项目指令要求代码任务不要主动跑测试或 build。
