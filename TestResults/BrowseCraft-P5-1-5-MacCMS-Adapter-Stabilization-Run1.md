# BrowseCraft P5.1.5 MacCMS Adapter Stabilization - Run 1

- 日期：2026-07-06
- 范围：`VideoAdapter.macCMS` 稳定化
- 类型：代码实现记录

## 完成内容

- `MacCMSVideoHTMLMapper` 内部新增 selector fallback 分组：
  - list items
  - detail links
  - titles
  - covers
  - latest text
  - episode links
  - player titles
- 保持 ewave/stui/myui/module-item 等皮肤在 MacCMS mapper 内部，不升级为新 adapter。
- 播放页空 `player_aaaa.url` 现在返回：

```text
SourceVideoPlaybackStatus.failed(.mediaURLNotFound)
```

- MP4 播放地址继续识别为 `.mp4` 并返回 `.playable`。
- `VideoAdapterDetector` 补充 MacCMS 信号：
  - `mac_history`
  - `macplayer`
  - `zanpian`
- 补充测试覆盖：
  - MacCMS 皮肤 selector fallback
  - MP4 播放地址
  - 空 player payload 明确失败
  - detector 从 route/html 识别 MacCMS

## 修改文件

```text
BrowseCraft/Application/Runtime/Video/Mapping/MacCMSVideoHTMLMapper.swift
BrowseCraft/Application/Runtime/Video/Mapping/VideoAdapterDetector.swift
BrowseCraftTests/Application/Video/VideoRuntimeMacCMSMappingTests.swift
TestResults/BrowseCraft-P5-Video-Runtime-Strategy-Plan.md
```

## 验证

已通过。

```text
xcodegen generate
结果：通过

env -u GEM_HOME -u GEM_PATH pod install
结果：通过

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet \
  -workspace /Users/xiefei/Desktop/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/VideoRuntimeMacCMSMappingTests \
  -only-testing:BrowseCraftTests/SourceRuntimeMappingTests
结果：通过
```
