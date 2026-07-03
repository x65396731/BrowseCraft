# BrowseCraft P1-4.1 RequestConfig Unit Tests Run 1

## 测试范围

中文注释：本记录用于保留 P1-4.1 的测试结果，重点确认 V2 `RequestConfig` 可以从规则模型传到 list/detail/reader 的网络请求入口。

- `BrowseCraftTests/RequestConfigUseCaseTests`
- `BrowseCraftTests/SiteRuleV2CompletenessTests`

## 前置处理

中文注释：`xcodegen generate` 后需要重新执行 `pod install`，让 `.xcworkspace` 重新集成 CocoaPods 依赖。

```sh
cd /Users/trs/test-git/BrowseCraft
pod install
```

结果：

- `Pod installation complete!`
- 5 dependencies / 6 total pods installed

## 执行命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -only-testing:BrowseCraftTests/SiteRuleV2CompletenessTests test
```

## 结果

- 执行时间：2026-07-03 15:16 +0900
- 结果：通过
- Swift Package：`BrowseCraftRulesKit @ main (6f54e9b)`
- Swift Testing：10 tests / 2 suites passed
- XCTest 兼容输出：0 tests executed, 0 failures
- xcresult：
  `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_15-15-53-+0900.xcresult`

## 覆盖点

- `Rule > Page > Site sharedRequest` 的 `RequestConfig` 选择优先级。
- 列表刷新把 list tab 对应 request 传入 `HTTPClient`。
- 详情章节加载把 detail request 传入 `HTTPClient`。
- 阅读页加载把 gallery request 传入 `HTTPClient`。
