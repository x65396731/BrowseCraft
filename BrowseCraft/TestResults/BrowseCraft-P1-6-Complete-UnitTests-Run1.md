# BrowseCraft P1-6 Complete Tests Run 1

中文注释：本记录用于保留 P1-6 完整性测试结果，覆盖内置源覆盖矩阵、Pepper&Carrot RulesKit 回归、一层源 App 边界和 package 刷新脚本检查。

## RulesKit Command

```sh
swift test
```

Working directory:

```text
/Users/trs/test-git/BrowseCraftRulesKit
```

Result:

- Status: Passed
- Tests: 3 passed
- Failures: 0

## App Command

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SiteRuleV2CompletenessTests -only-testing:BrowseCraftTests/SwiftSoupListParserTests -only-testing:BrowseCraftTests/SwiftSoupDetailParserTests -only-testing:BrowseCraftTests/SwiftSoupReaderParserTests -only-testing:BrowseCraftTests/RequestConfigUseCaseTests test
```

Result:

- Status: Passed
- Test suites: 5
- Tests: 30 passed
- Failures: 0
- Xcode: `/Applications/Xcode-26.0.1.app/Contents/Developer`
- Swift Package resolved: `BrowseCraftRulesKit @ main (6f54e9b)`

## Script Checks

```sh
sh -n BrowseCraft/scripts/update-rules-package.sh
```

Result: Passed

```sh
./scripts/update-rules-package.sh --help
```

Result: Passed

```sh
./scripts/update-rules-package.sh --dry-run
```

Result: Expected failure

```text
[update-rules-package] ERROR: BrowseCraftRulesKit has uncommitted changes. Commit/push or stash them before updating the app package.
```

中文注释：当前 `BrowseCraftRulesKit` 仍有 P1-6.2 的未提交测试改动，dry-run 在远端读取和 `Package.resolved` 写入前停止，说明 dirty guard 生效。

## Covered Scope

- P1-6.1: 覆盖矩阵与现有测试证据整理。
- P1-6.2: Pepper&Carrot list selector RulesKit 回归。
- P1-6.3: Pepper&Carrot 一层列表直达 reader 的 App 用例边界。
- P1-6.4: package 刷新脚本 `--dry-run` / `--check` 行为边界。

## Not Run

- 中文注释：本次未执行默认 package 刷新模式。
- 中文注释：本次未执行 `pod install`。
- 中文注释：本次未执行 UI 测试。
