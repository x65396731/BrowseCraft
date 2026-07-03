# BrowseCraft P2-2.5 Rule Package Boundary Unit Tests Run 1

中文注释：本记录用于保留 P2-2 规则包核心边界测试结果；`.xcresult` 仅作为本机临时结果包，不作为长期提交物。

## Preparation

中文注释：本次只验证 P2-2 规则包业务边界；未重新执行 `xcodegen generate` 或 `pod install`。

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RulePackageUseCaseTests -resultBundlePath /private/tmp/BrowseCraft-P2-2-5-RulePackageBoundaries-UnitTests.xcresult
```

## Result

- Status: Passed
- Test suites: 1
- Tests: 10 passed
- Failures: 0
- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Swift Package resolved: `BrowseCraftRulesKit @ main (cfcbd75)`

## Result Bundle

```text
/private/tmp/BrowseCraft-P2-2-5-RulePackageBoundaries-UnitTests.xcresult
```

中文注释：该 `.xcresult` 位于临时目录，可用于本机短期复查日志；长期记录以本 Markdown 为准。

## Covered Scope

- P2-2: Encode/decode BrowseCraft rule package JSON envelope.
- P2-2: Reject checksum mismatch.
- P2-2: Reject unsupported package kind.
- P2-2: Reject unsupported format version.
- P2-2: Export latest user source rule with stable metadata and filename.
- P2-2: Reject exporting a missing source.
- P2-2: Allow exporting a built-in Source package.
- P2-2: Import a valid package as a user `Source`.
- P2-2: Preserve existing local Source when imported package metadata reuses an existing `sourceID`.
- P2-2: Preserve local built-in Source when importing a package whose metadata contains a `built-in.*` sourceID.

## Not Run

- 中文注释：本次未执行全量 `BrowseCraftTests`。
- 中文注释：本次未执行 UI 自动化测试。
- 中文注释：本次未执行单独的 build 命令。
