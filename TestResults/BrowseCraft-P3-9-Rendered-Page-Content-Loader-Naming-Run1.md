# BrowseCraft P3-9 Rendered Page Content Loader Naming - Run 1

- 日期：2026-07-05
- 范围：Domain 页面渲染加载协议命名中性化。
- 目标：避免 Domain 服务协议暴露具体 `WebView` 技术名，让 Domain 只表达“获取渲染后的页面内容”这一能力。

## 改动

- `BrowseCraft/Domain/Services/WebViewContentLoader.swift` -> `BrowseCraft/Domain/Services/RenderedPageContentLoader.swift`
- `WebViewContentLoader` -> `RenderedPageContentLoader`
- `DefaultPageContentLoader.webViewContentLoader` -> `DefaultPageContentLoader.renderedPageContentLoader`
- 测试 fake `RecordingWebViewContentLoader` -> `RecordingRenderedPageContentLoader`
- `WKWebViewHTMLLoader` 保留技术名，因为它位于 Infrastructure，确实是 WebKit 实现。

## 不变项

- 不改变 `needsWebView` rule 字段。
- 不改变 HTTP/WebView 分流行为。
- 不改变 `WKWebViewHTMLLoader` 实现。
- 不改变 runtime-first / source-configuration 主轴。

## XcodeGen / Pod

- 已运行：`./scripts/regenerate-project.sh`
- 结果：XcodeGen 成功，`pod install` 成功。
- 生成物未产生待提交状态。

## 测试

命令：

```sh
xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath TestResults/P3-9-13-Rendered-Page-Content-Loader-Naming-Run2.xcresult -only-testing:BrowseCraftTests/PageContentLoaderTests -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -only-testing:BrowseCraftTests/SourceRuntimeMappingTests
```

结果：

- 通过：30 tests / 3 suites。
- 失败：0。
- `.xcresult`：`TestResults/P3-9-13-Rendered-Page-Content-Loader-Naming-Run2.xcresult`。

## 当前 Domain/Services 结构

```text
CookieHeaderResolver.swift
HTTPClient.swift
RenderedPageContentLoader.swift
RuleCandidateAnalyzingService.swift
RuleParsingService.swift
URLResolvingService.swift
```

## 偏航检查

- live 源码和测试中无 `WebViewContentLoader` / `webViewContentLoader` / `RecordingWebViewContentLoader`。
- live 源码和测试中无 `Bridge` / `Adapter` / `unsupportedPersistedSourceKind`。
- Core repo 未改动。
- `git diff --check` 通过。

## 下一步

- P3-9 仍可冻结。
- 下一节：进入 P3-10 计划细化。
- 计划是否需要更新：P3-9 不需要新增功能计划；P3-10 需要新建或细化计划。
