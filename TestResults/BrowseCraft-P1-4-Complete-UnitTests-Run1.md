# BrowseCraft P1-4 完整性单元测试记录

## 测试目的

中文注释：本次完整性测试覆盖 BrowseCraftTests 全量单元测试集合，确认 P1-4.1 到 P1-4.4 的 RequestConfig、图片请求、WebView 分流、Cookie header 能力没有破坏既有模型、解析器和用例行为。

## 前置刷新

- 执行 `xcodegen generate`，重新生成本地 Xcode 工程。
- 执行 `pod install`，在重新生成工程后恢复 CocoaPods 集成。
- 使用当前指定 Xcode：`/Applications/Xcode-26.0.1.app/Contents/Developer`。
- Swift Package 解析结果：`BrowseCraftRulesKit @ main (6f54e9b)`。
- 本次只跑 `BrowseCraftTests` 单元测试集合，不包含 UI 测试。

## 测试命令

```bash
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild \
  -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests \
  test
```

## 测试结果

- 结果：通过。
- Swift Testing：45 tests / 13 suites passed。
- XCTest 外层：0 failures。
- xcresult：
  `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_15-40-25-+0900.xcresult`

## 覆盖范围

- `CookieHeaderResolverTests`
  - 中文注释：覆盖 Cookie 策略和同名 Cookie 优先级。
- `ImageRequestFactoryTests`
  - 中文注释：覆盖图片 header、Referer、imageRequest Cookie 策略。
- `PageContentLoaderTests`
  - 中文注释：覆盖 HTTP 默认路径和 WebView 分流路径。
- `RequestConfigUseCaseTests`
  - 中文注释：覆盖列表、详情、阅读页 request config 到页面加载入口的传递。
- `RequestConfigModelTests`
  - 中文注释：覆盖 RequestConfig / ImageRequestConfig Codable 兼容性。
- 模型测试
  - 中文注释：覆盖 ExtractRule、Field、NestedRule、SiteRuleV2、URLTemplate 等 V2 模型结构。
- 解析器测试
  - 中文注释：覆盖 SwiftSoup 列表、详情章节、阅读页图片解析，以及 V2 PageRuleRefs 流程。

## 备注

中文注释：测试日志中存在预期内的解析 debug 输出，例如 fixture 中故意放入非 JSON 数据以覆盖 fallback 路径；最终测试结果为全量通过。
