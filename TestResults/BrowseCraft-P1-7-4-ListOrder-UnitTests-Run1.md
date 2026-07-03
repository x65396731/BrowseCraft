# BrowseCraft P1-7.4 List Order Unit Tests Run 1

中文注释：本记录用于保留 P1-7.4 列表缓存顺序修正的最小验证结果，方便后续提交和回归时确认测试范围。

## Environment

- Date: 2026-07-03
- Xcode: `/Applications/Xcode-26.0.1.app/Contents/Developer`
- Workspace: `/Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace`
- Scheme: `BrowseCraft`
- Destination: `iPhone 17 Pro`, iOS 26.0.1 Simulator
- Swift Package resolved: `BrowseCraftRulesKit @ main (cfcbd75)`

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer \
xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  test
```

## Result

- Final result: passed.
- Test suite: `RequestConfigUseCaseTests`
- Tests: 7 passed, 0 failed.
- xcresult: `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_18-22-04-+0900.xcresult`

## Covered Assertion

- 中文注释：新增 `contentCachePreservesListOrderWhenLoadingSelectedTab`，验证 GRDB 读取指定 source/tab/listRule 缓存时按 `listOrder` 恢复列表顺序。
- 中文注释：测试特意让 `updatedAt` 和 `listOrder` 方向相反，确认缓存读取不会再被更新时间打乱。

## Notes

- 中文注释：本次只运行 `RequestConfigUseCaseTests` 目标测试范围，未执行 UI 测试，未执行全量回归。
- 中文注释：未执行 `pod install`、Swift Package refresh、commit 或 push。
