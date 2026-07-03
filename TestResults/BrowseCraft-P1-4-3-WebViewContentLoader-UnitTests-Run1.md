# BrowseCraft P1-4.3 WebView Content Loader 单元测试记录

## 测试目的

中文注释：本次测试确认 `RequestConfig.needsWebView` 已经接入页面内容加载入口，并且默认规则仍走普通 HTTP，不影响既存原生列表、详情、阅读页流程。

## 前置刷新

- 执行 `xcodegen generate`，重新生成本地 Xcode 工程。
- 执行 `pod install`，在重新生成工程后恢复 CocoaPods 集成。
- 使用当前指定 Xcode：`/Applications/Xcode-26.0.1.app/Contents/Developer`。
- Swift Package 解析结果：`BrowseCraftRulesKit @ main (6f54e9b)`。

## 测试命令

```bash
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild \
  -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/PageContentLoaderTests \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  -only-testing:BrowseCraftTests/RequestConfigModelTests \
  -only-testing:BrowseCraftTests/ImageRequestFactoryTests \
  test
```

## 测试结果

- 结果：通过。
- Swift Testing：9 tests / 4 suites passed。
- XCTest 外层 selected tests：0 failures。
- xcresult：
  `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_15-32-46-+0900.xcresult`

## 覆盖点

- `PageContentLoaderTests`
  - 中文注释：验证未声明 `needsWebView` 时继续走 HTTP，保护既存站点默认抓取行为。
  - 中文注释：验证声明 `needsWebView = true` 时绕过 HTTP，交给 WebView loader 获取渲染后的 HTML。
- `RequestConfigUseCaseTests`
  - 中文注释：验证列表、详情、阅读页仍能把对应 request config 传入页面加载入口。
- `RequestConfigModelTests`
  - 中文注释：验证 `needsWebView`、`autoScroll` 和图片请求配置的 Codable 结构仍可解码。
- `ImageRequestFactoryTests`
  - 中文注释：回归验证图片请求 header / Referer 合并逻辑未受 P1-4.3 影响。

## 备注

中文注释：本次测试使用 fake WebView loader 验证分流逻辑，没有启动真实 WKWebView 访问外部网站；真实 WebView 渲染行为适合后续结合需要 JS 的实际站点做集成验证。
