# BrowseCraft P2-1 Complete Unit Tests Run 1

中文注释：本记录用于保留 P2-1 规则编辑器与规则管理完整性单元测试结果；`.xcresult` 仅作为本机临时结果包，不作为长期提交物。

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
/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.03_22-07-14-+0900.xcresult
```

中文注释：该 `.xcresult` 位于 DerivedData，可用于本机复查日志；长期记录以本 Markdown 为准。

## Covered Scope

- P2-1.1: Sources 规则详情入口、内置/用户规则边界。
- P2-1.2: Rule Detail 基础结构摘要背后的模型读取。
- P2-1.3: JSON decode / validation / formatting 复用链路。
- P2-1.4: 基础字段编辑保存链路复用规则更新用例。
- P2-1.5: RuleValidator 结构校验、ruleRefs 校验、重复 id 校验。
- P2-1.6: 用户规则保存、内置规则只读、复制为用户规则、旧草稿防覆盖。
- Resolved rule graph 回归：V2 detail/gallery page-rule 配对与主规则解析未回退。
- P1 主链路回归：请求配置、列表/详情/阅读解析、缓存顺序、Cookie/Image/WebView 最小路径。

## Key Passing Tests

- `RuleManagementUseCaseTests`
- `SiteRuleV2CompletenessTests`
- `RequestConfigUseCaseTests`
- `SwiftSoupListParserTests`
- `SwiftSoupDetailParserTests`
- `SwiftSoupReaderParserTests`

## Notes

- 中文注释：测试期间出现 iOS Simulator WebCore/WebKit accessibility duplicate class warning；测试未失败，当前判断为模拟器运行时噪声。

## Not Run

- 中文注释：本次未执行 UI 自动化测试。
- 中文注释：本次未执行单独的 build 命令。
