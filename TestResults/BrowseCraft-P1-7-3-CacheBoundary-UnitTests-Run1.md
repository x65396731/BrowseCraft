# BrowseCraft P1-7.3 Cache Boundary Unit Tests Run 1

中文注释：本记录用于保留 P1-7.3 缓存边界最小验证结果，方便后续提交和回归时确认测试范围。

## Environment

- Date: 2026-07-03
- Xcode: `/Applications/Xcode-26.0.1.app/Contents/Developer`
- Workspace: `/Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace`
- Scheme: `BrowseCraft`
- Destination: `iPhone 17 Pro`, iOS 26.0.1 Simulator
- Swift Package resolved: `BrowseCraftRulesKit @ main (690279d)`

## Commands

```sh
xcodegen generate
pod install
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer \
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  test
```

## Result

- Final result: passed.
- Test suite: `RequestConfigUseCaseTests`
- Tests: 6 passed, 0 failed.

## Covered Assertion

- 中文注释：新增 `refreshSourceReplacesOnlySelectedTabCache`，验证 P1-7.3 的缓存边界是 `source + tab + listRule`。
- 中文注释：测试确认刷新 `discover/home-list` 后，旧 discover 缓存被替换为新结果，而 `latest/latest-list` 缓存不被删除、不混入当前 tab。

## Notes

- 中文注释：第一次执行失败是因为新增 `Shared/Errors`、`Shared/Logging` 文件尚未被当前 `.xcodeproj` 收录，表现为找不到 `RuleExecutionError`。
- 中文注释：执行 `xcodegen generate` 后第二次失败是因为 CocoaPods 依赖尚未重新集成，表现为找不到 `Alamofire`、`GRDB`、`Nuke`、`NukeUI`、`SwiftSoup`。
- 中文注释：执行 `pod install` 后重跑同一最小测试范围，最终通过；未执行 UI 测试，未执行全量回归。
