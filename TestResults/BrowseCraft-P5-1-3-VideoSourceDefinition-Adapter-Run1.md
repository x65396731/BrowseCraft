# BrowseCraft P5.1.3 VideoSourceDefinition Adapter - Run 1

- 日期：2026-07-06
- 范围：视频 source 长期模型从 `siteKind` 迁移到 `adapter`
- 类型：代码实现记录

## 完成内容

- 在 BrowseCraftCore 中新增长期模型字段：
  - `VideoSourceDefinition.adapter`
  - `VideoAdapter.macCMS`
  - `VideoAdapter.genericHTML`
  - `VideoAdapter.iframe`
  - `VideoAdapter.webView`
  - `VideoAdapter.plugin`
- 将 `VideoSourceDefinition.routePatterns` 改为可选，方便非 MacCMS adapter 后续不携带 MacCMS 路由模板。
- 保留旧数据兼容：
  - 旧 JSON `siteKind = macCMS` 解码为 `adapter = macCMS`
  - 旧 MacCMS 数据缺少 `routePatterns` 时默认补 `.macCMS`
- 新编码只写 `adapter`，不再写旧 `siteKind`。
- App 侧调用点从 `siteKind` 切到 `adapter`：
  - `AddVideoSourceUseCase`
  - `BuiltInSource`
  - `SourceRuntimeFactory`
  - `ResolveLibrarySourcePresentationUseCase`
  - `VideoRuntimeMacCMSMappingTests`
- `VideoAdapterDetector` 改为使用 BrowseCraftCore 的 `VideoAdapter`，避免 App 内重复定义。

## 修改文件

```text
BrowseCraftCore/Sources/BrowseCraftCore/Source/VideoSourceDefinitionModels.swift
BrowseCraftCore/Tests/BrowseCraftCoreTests/SourceDefinitionTests.swift
BrowseCraft/Application/Runtime/SourceRuntimeFactory.swift
BrowseCraft/Application/Runtime/Video/Mapping/VideoAdapterDetector.swift
BrowseCraft/Application/UseCases/Library/ResolveLibrarySourcePresentationUseCase.swift
BrowseCraft/Application/UseCases/Source/AddVideoSourceUseCase.swift
BrowseCraft/Domain/Models/Source/BuiltInSource.swift
BrowseCraftTests/Application/Video/VideoRuntimeMacCMSMappingTests.swift
TestResults/BrowseCraft-P5-Video-Runtime-Strategy-Plan.md
```

## 验证

### CocoaPods

```text
env -u GEM_HOME -u GEM_PATH pod install
```

结果：通过。

### BrowseCraftCore

第一次直接运行 `swift test` 失败，原因是 CommandLineTools SwiftPM manifest link 环境不匹配。

随后使用 Xcode toolchain：

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

结果：通过。

```text
41 tests passed, 0 failures.
```

新增覆盖：

- `testLegacyVideoSiteKindDecodesAsMacCMSAdapter`
- `testVideoDefinitionEncodesAdapterWithoutLegacySiteKind`

### BrowseCraft App 定向测试

```text
xcodebuild test
  -workspace /Users/xiefei/Desktop/BrowseCraft/BrowseCraft.xcworkspace
  -scheme BrowseCraft
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"
  -only-testing:BrowseCraftTests/VideoRuntimeMacCMSMappingTests
  -only-testing:BrowseCraftTests/SourceRuntimeMappingTests
```

结果：通过。

```text
13 tests passed, 0 failures.
```
