# BrowseCraft P3-5.7 Resolved Graph Core Migration Tests Run 1

中文注释：本记录用于保留 P3-5.7 将 `ResolvedSiteRule` / `RuleResolver` 迁入 `BrowseCraftCore` 后的测试结果；`.xcresult` 仅作为本机临时结果包，不作为长期提交物。

## Environment

- Date: 2026-07-04
- Machine Xcode: `/Applications/Xcode.app/Contents/Developer`
- Xcode version: Xcode 26.6, Build 17F113
- Note: `current-work.md` 旧记录要求 `/Applications/Xcode-26.0.1.app/Contents/Developer`，但本机不存在该路径；本轮改用实际安装的 Xcode 26.6。

## Scope

- BrowseCraftCore `swift test`
- BrowseCraft main app unit tests: `BrowseCraftTests`
- No UI tests were run.
- No `xcodegen generate` or `pod install` was run.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests \
  -derivedDataPath /private/tmp/BrowseCraft-P3-5-7-DerivedData \
  -resultBundlePath /private/tmp/BrowseCraft-P3-5-7-App.xcresult
```

## Results

### BrowseCraftCore

- Result: Passed
- Tests: 20 tests, 0 failures
- New P3-5.7 coverage:
  - `ResolvedSiteRuleTests.testResolvedDetailAndGalleryEntriesKeepPageRulePairing`
  - `ResolvedSiteRuleTests.testResolvedContextsExposeRequestSnapshotsWithoutRuleTuples`
  - `ResolvedSiteRuleTests.testResolvedRuleFallsBackToLegacyDetailAndGalleryRules`

### BrowseCraftTests

- Result: Passed
- Tests: 112 tests in 22 suites, 0 failures
- Result bundle: `/private/tmp/BrowseCraft-P3-5-7-App.xcresult`

## Notes

- Xcode resolved `BrowseCraftRulesKit` at `main (cfcbd75)`.
- The app test build compiled the migrated Core file `ResolvedSiteRule.swift` through the local package reference.
- Existing non-fatal Swift Testing warnings remain in `RulePackageUseCaseTests.swift` for `#expect(true)` and are unrelated to P3-5.7.
