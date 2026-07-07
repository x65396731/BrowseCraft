# BrowseCraft P5.1.12 WebViewRequired Run 1

- 日期：2026-07-07
- 范围：
  - `BrowseCraftTests/VideoSourceDetectionTests`
  - `BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests`

## 命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild test -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests
```

## 结果

- 状态：通过
- Swift Testing：18 tests / 2 suites / 0 failures
- xcodebuild：`** TEST SUCCEEDED **`
- `.xcresult`：

```text
/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-ekyodtkldclxfmcsueisismacgpi/Logs/Test/Test-BrowseCraft-2026.07.07_10-25-22-+0900.xcresult
```

## 覆盖点

- JS shell / SPA HTML 被识别为 `renderMode = .webViewRequired`，同时不强制进入 plugin。
- `VideoSourceRenderingGuard` 会在 list / playback 静态 mapper 前拒绝 WebViewRequired HTML。
- unsupported 信息包含 WebView rendering、not connected 和 `webViewRequired`，便于 UI/debug 识别真实原因。
- GenericHTML 既有列表、详情、HTML5 player、JSON-LD、iframe pageOnly 行为仍通过原有测试。

## 备注

- Xcode 输出中 XCTest 汇总显示 `Executed 0 tests` 是 Swift Testing 用例的常见显示差异；实际 Swift Testing 汇总为 18 tests 全部通过。
