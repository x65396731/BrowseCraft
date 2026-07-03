# BrowseCraftRulesKit P1-6.2 Pepper&Carrot List Unit Tests Run 1

中文注释：本记录用于保留 P1-6.2 的规则包测试结果，重点确认 Pepper&Carrot 列表规则会匹配文字 episode 链接，而不是误选封面图片链接。

## Command

```sh
swift test
```

## Working Directory

```text
/Users/trs/test-git/BrowseCraftRulesKit
```

## Result

- Status: Passed
- Test suites: `BrowseCraftRulesKitTests`
- Tests: 3 passed
- Failures: 0

## Covered Tests

- `primaryBuiltInRuleJSONIsValidObject`
- `pepperCarrotReaderImageRuleMatchesEpisodePages`
- `pepperCarrotListRuleMatchesTextEpisodeLinks`

## Notes

- 中文注释：本次只运行 `BrowseCraftRulesKit` 的 Swift Package 单元测试。
- 中文注释：本次没有运行 App 侧 `xcodebuild`，没有执行 `pod install`，也没有刷新 Swift Package。
