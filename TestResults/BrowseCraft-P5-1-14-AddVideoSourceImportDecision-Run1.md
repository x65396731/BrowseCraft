# BrowseCraft P5.1.14 AddVideoSource Import Decision Run 1

- 日期：2026-07-07
- 范围：
  - `BrowseCraftTests/VideoTabDiscoveryTests`
  - `BrowseCraftTests/VideoSourceDetectionTests`
  - `BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests`

## 命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild test -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoTabDiscoveryTests -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests
```

## 结果

- 状态：通过
- Swift Testing：34 tests / 3 suites / 0 failures
- xcodebuild：`** TEST SUCCEEDED **`
- `.xcresult`：

```text
/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-ekyodtkldclxfmcsueisismacgpi/Logs/Test/Test-BrowseCraft-2026.07.07_11-22-13-+0900.xcresult
```

## 覆盖点

- `AddVideoSourceUseCase` 高置信 built-in 视频来源保存为 `.saved`。
- 未提供 HTML 的视频来源返回 `.needsReview`，不直接保存；用户确认后可通过 `saveReviewedSource` 保存。
- `no video signals` / unavailable 分支返回 `.unavailable`，不保存 source。
- 强 plugin 信号返回 `.pluginRequired`，不保存 source。
- P5.1.13 的 detection/import decision 分支和 GenericHTML/WebViewRequired 映射回归仍通过。

## 备注

- 第一次运行构建失败，原因是 `AddSourceView` 中方法名使用 Swift 关键字 `import`；已改为 `startImport`。
- 第二次运行进入测试后有 2 个新用例失败，原因是测试 URL path 先被 `VideoSourceURLResolver` 判为 unsupported，未进入 import decision 分支；已把测试输入调整为有效站点入口 URL 后重跑通过。
- Xcode 输出中 XCTest 汇总显示 `Executed 0 tests` 是 Swift Testing 用例的常见显示差异；实际 Swift Testing 汇总为 34 tests 全部通过。
