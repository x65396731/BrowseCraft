# BrowseCraft P5.1.7 GenericHTMLVideoHTMLMapper - Run 1

- 日期：2026-07-06
- 范围：`VideoAdapter.genericHTML` 内置 mapper
- 类型：代码实现记录

## 完成内容

- 新增 `GenericHTMLVideoHTMLMapper`。
- `VideoAdapterRegistry` 将 `.genericHTML` 接到 `GenericHTMLVideoHTMLMapper`。
- `BuiltInSource` 新增 GenericHTML 视频测试源，并只配置最小首页入口；后续 tab 数量应来自检测/用户配置，不在内置源里拍脑袋固定。
- `VideoSourceConfiguration` 新增 `listTabs`，视频列表 tab 改为配置驱动。
- `ResolveLibrarySourcePresentationUseCase` 只把视频配置 tab 映射成 Library 横向 tab，不再按 adapter 固定分类。
- `RefreshSourceRuntimeUseCase` 会把选中的视频 tab URL 写入 `requestOverride`，`VideoSourceListLoader` 不再硬编码 MacCMS 分类 URL。
- 支持静态 HTML 列表抽取：
  - `.frame-block.thumb-block`
  - 按优先级分组匹配 `article` / `.video-card` / `.card` / `.item` / `.video` / `li`
  - `a[href]` 详情链接
  - `img[data-src]` / `img[src]` 封面
  - `title` / `alt` / text 标题
  - `.duration` 等元信息
- 支持播放页抽取：
  - `html5player.setVideoHLS(...)`
  - `html5player.setVideoUrlHigh(...)`
  - `html5player.setVideoUrlLow(...)`
  - JSON-LD `contentUrl`
  - `video/source[src]`
  - `iframe[src]`
- GenericHTML 详情页按 video/genericHTML adapter 语义作为单视频播放页处理，只返回当前页一个 episode，避免依赖页面数据猜测类型或把推荐/导航链接误识别成剧集。
- 新增 `VideoRuntimeGenericHTMLMappingTests`。
- 新增真实 genericHTML 样本 fixtures：

```text
BrowseCraftTests/Fixtures/Video/GenericHTML/xvideos-home.html
BrowseCraftTests/Fixtures/Video/GenericHTML/xvideos-detail.html
```

## 修改文件

```text
BrowseCraft/Application/Runtime/Video/Mapping/GenericHTMLVideoHTMLMapper.swift
BrowseCraft/Application/Runtime/Video/Mapping/VideoAdapterRegistry.swift
BrowseCraft/Application/Runtime/Video/Loading/VideoSourceListLoader.swift
BrowseCraft/Application/UseCases/Library/ResolveLibrarySourcePresentationUseCase.swift
BrowseCraft/Application/UseCases/Source/AddVideoSourceUseCase.swift
BrowseCraft/Application/UseCases/Source/RefreshSourceRuntimeUseCase.swift
BrowseCraft/Domain/Models/Source/BuiltInSource.swift
BrowseCraft/Domain/Models/Source/SourceConfiguration.swift
BrowseCraftTests/Application/Video/VideoRuntimeGenericHTMLMappingTests.swift
BrowseCraftTests/Fixtures/Video/GenericHTML/xvideos-home.html
BrowseCraftTests/Fixtures/Video/GenericHTML/xvideos-detail.html
TestResults/BrowseCraft-P5-Video-Runtime-Strategy-Plan.md
```

## 验证

本次追加的视频 tab 配置驱动改造未运行测试/build。

历史 P5.1.7 定向测试记录：

已运行定向测试：

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -workspace /Users/xiefei/Desktop/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests
```

结果：通过。

备注：测试前曾运行 `xcodegen generate` 和 `pod install`，因为本阶段新增了源码与 fixture 文件，需要同步 XcodeGen 工程和 CocoaPods workspace。

已知 warning：

```text
Metal toolchain iphonesimulator search path not found
Patch FFmpegKit Bundle Identifiers script phase will run during every build
```

以上 warning 未导致测试失败。
