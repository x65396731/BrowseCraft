# BrowseCraft P1-4.4 Cookie Header 单元测试记录

## 测试目的

中文注释：本次测试确认 `RequestConfig.cookiePolicy` / `cookiePriority` 已经在请求头层实际生效，并且不会破坏 P1-4.1 到 P1-4.3 已完成的请求配置、图片请求和 WebView 分流能力。

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
  -only-testing:BrowseCraftTests/CookieHeaderResolverTests \
  -only-testing:BrowseCraftTests/ImageRequestFactoryTests \
  -only-testing:BrowseCraftTests/PageContentLoaderTests \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  -only-testing:BrowseCraftTests/RequestConfigModelTests \
  test
```

## 测试结果

- 结果：通过。
- Swift Testing：15 tests / 5 suites passed。
- XCTest 外层 selected tests：0 failures。
- xcresult：
  `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_15-38-21-+0900.xcresult`

## 覆盖点

- `CookieHeaderResolverTests`
  - 中文注释：验证 `custom` 策略只使用规则 Cookie。
  - 中文注释：验证 `browser` 策略只使用浏览器 Cookie。
  - 中文注释：验证 `browserThenCustom` 在 custom 优先时保留浏览器独有 Cookie，并用规则 Cookie 覆盖同名值。
  - 中文注释：验证 `browserThenCustom` 在 browser 优先时保留规则独有 Cookie，并用浏览器 Cookie 覆盖同名值。
  - 中文注释：验证 `none` 策略会移除 Cookie header，避免被状态污染。
- `ImageRequestFactoryTests`
  - 中文注释：验证图片请求的 `imageRequest.cookiePolicy` 能覆盖页面级 Cookie 策略。
  - 中文注释：回归验证图片 header 与 Referer 合并逻辑。
- `PageContentLoaderTests`
  - 中文注释：回归验证 WebView 分流逻辑没有被 Cookie 接线破坏。
- `RequestConfigUseCaseTests`
  - 中文注释：回归验证列表、详情、阅读页 request config 仍能传到页面加载入口。
- `RequestConfigModelTests`
  - 中文注释：回归验证 RequestConfig / ImageRequestConfig Codable 结构保持兼容。

## 备注

中文注释：本次测试使用显式传入的 fake browser Cookie 字符串验证合并规则，没有依赖全局 `HTTPCookieStorage` 的真实浏览器状态，因此结果稳定可重复。
