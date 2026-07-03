# BrowseCraft P2-1.6 Save Version Boundary Tests Run 1

中文注释：本记录用于保留 P2-1.6 保存与版本边界测试结果；`.xcresult` 仅作为本机临时结果包，不作为长期提交物。

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests
```

## Result

- Status: Passed
- Test suites: 14
- Tests: 65 passed
- Failures: 0
- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Swift Package resolved: `BrowseCraftRulesKit @ main (cfcbd75)`

## Result Bundle

```text
/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.03_22-01-30-+0900.xcresult
```

中文注释：该 `.xcresult` 位于 DerivedData，可用于本机复查日志，但不需要提交；长期记录以本 Markdown 为准。

## Covered Scope

- P2-1.6: `UpdateSourceRuleUseCase` 保存前读取 repository 中最新 `Source`。
- P2-1.6: 内置规则仍拒绝直接编辑。
- P2-1.6: `expectedUpdatedAt` 阻止旧草稿覆盖已更新的用户规则。
- P2-1.6: `RuleDetailView` JSON / Basic 保存链路带回打开编辑器时的 source 更新时间。

## Key Passing Test

- `RuleManagementUseCaseTests.updateSourceRuleRejectsStaleDraftVersion`

## Not Run

- 中文注释：本次未执行 UI 测试。
- 中文注释：本次未执行单独的 build 命令。
