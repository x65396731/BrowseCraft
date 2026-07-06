# BrowseCraft P5.1.8 VideoTabDiscovery Run 1

日期：2026-07-07

## 目标

把视频 tab 从 UI/默认值硬编码中拆出来，形成 `SourceRuntimeKind.video` 通用的 tab discovery 层：

- MacCMS 根据页面真实 `/vodtype/`、`/vodshow/` 链接发现 tab。
- GenericHTML 根据首页导航/分类区的同站链接发现 tab。
- 未发现时只保底 `video.home`，不凭空补固定分类。
- `VideoHTMLMapper` 继续只负责 list/detail/playback，不承担 tab discovery。

## 已完成

新增 discovery 层：

```text
BrowseCraft/Application/Runtime/Video/Discovery/VideoTabDiscoverer.swift
BrowseCraft/Application/Runtime/Video/Discovery/VideoTabDiscovererRegistry.swift
BrowseCraft/Application/Runtime/Video/Discovery/MacCMSVideoTabDiscoverer.swift
BrowseCraft/Application/Runtime/Video/Discovery/GenericHTMLVideoTabDiscoverer.swift
```

接入点：

```text
BrowseCraft/Application/UseCases/Source/AddVideoSourceUseCase.swift
```

`AddVideoSourceUseCase.execute` 现在可接收 `entryHTML` 和 `headers`。当上层提供入口页 HTML 时：

```text
entryHTML
  -> VideoAdapterDetector
  -> VideoTabDiscovererRegistry
  -> [VideoSourceListTab]
  -> VideoSourceConfiguration.listTabs
```

没有 `entryHTML` 时保持不主动联网，只返回首页 tab fallback。

新增测试：

```text
BrowseCraftTests/Application/Video/VideoTabDiscoveryTests.swift
```

测试覆盖：

- MacCMS 只使用页面中实际发现的分类链接，不固定 5 个 tab。
- GenericHTML 从同站导航发现多个 tab，并排除登录/广告等入口。
- GenericHTML 无可信入口时只 fallback 首页。
- `AddVideoSourceUseCase` 在提供 HTML 时能持久化发现到的 GenericHTML tabs。

## 测试

用户要求“测试”后执行：

```text
xcodegen generate
env -u GEM_HOME -u GEM_PATH pod install
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoTabDiscoveryTests
```

结果：

```text
VideoTabDiscoveryTests：4 tests passed
TEST SUCCEEDED
```

xcresult：

```text
/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-cmivihkzqbasvdgazoybpgpjhgvv/Logs/Test/Test-BrowseCraft-2026.07.07_06-53-32-+0900.xcresult
```

## 后续

- AddVideoSource UI/流程层需要在保存视频源前抓取入口 HTML，并把 HTML 传入 `AddVideoSourceUseCase`。
- 内置测试源要动态发现 tab，需要单独的刷新/迁移流程；不应在 `BuiltInSource` 里继续增加硬编码分类。
