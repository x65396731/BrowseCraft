# BrowseCraft P1-4.2 Image Request Headers 单元测试记录

## 测试目的

中文注释：本次测试确认规则模型中的图片请求配置已经能进入 UI 图片加载路径，避免需要 Referer 或特殊图片 header 的站点在列表封面、章节封面、阅读页图片中加载失败。

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
  -only-testing:BrowseCraftTests/ImageRequestFactoryTests \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  -only-testing:BrowseCraftTests/RequestConfigModelTests \
  test
```

## 测试结果

- 结果：通过。
- Swift Testing：7 tests / 3 suites passed。
- XCTest 外层 selected tests：0 failures。
- xcresult：
  `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_15-23-44-+0900.xcresult`

## 覆盖点

- `ImageRequestFactoryTests`
  - 中文注释：验证 `imageHeaders` 会进入 Nuke 的 `URLRequest`。
  - 中文注释：验证 `imageRequest.headers` 优先级高于 `imageHeaders` 和当前页面 Referer。
  - 中文注释：验证规则未提供 Referer 时，会继续使用当前页面 URL 作为 Referer，保持旧版图片加载行为。
- `RequestConfigUseCaseTests`
  - 中文注释：验证列表、详情、阅读页请求仍按 P1-4.1 的规则粒度传入 HTTPClient。
- `RequestConfigModelTests`
  - 中文注释：验证 request config / image request config 的 Codable 结构仍可解码。

## 备注

中文注释：首次测试发现测试代码直接访问 Nuke `ImageRequest.urlRequest` 可选值导致编译失败；已改为先 `#require` 非空，再断言 header 内容。该修正只影响测试断言写法，不改变业务实现。
