# BrowseCraft P3-7.11 Completeness Regression Run 1

- Date: 2026-07-04
- Scope: P3-7 runtime-first completeness regression.

## Core

- Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test`
- Working directory:
  `/Users/xiefei/Desktop/BrowseCraftCore`
- Result: Passed.
- Total: 34 XCTest tests passed, 0 failures.
- Covered suites:
  - `ResolvedSiteRuleTests`
  - `RulePackageCodecTests`
  - `RuleValidatorTests`
  - `SiteRuleTests`
  - `SourceDefinitionTests`
  - `SourceRuleCandidateDraftApplierTests`
  - `SourceRuntimeHelperTests`

## App

- Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests -derivedDataPath /private/tmp/BrowseCraft-P3-7-11-AppTests-DerivedData -resultBundlePath /private/tmp/BrowseCraft-P3-7-11-AppTests-Run1.xcresult`
- Result: Passed.
- Total: 108 tests in 22 suites passed, 0 failures.
- Result bundle:
  `/private/tmp/BrowseCraft-P3-7-11-AppTests-Run1.xcresult`

## Regression Focus

- Runtime resolver and runtime-facing list refresh.
- Library runtime refresh, cache context, and list order behavior.
- Request config priority across list/detail/reader/search.
- Direct-reader behavior remains covered and passing.
- Rule management and rule package import/export remain covered and passing.
- Core runtime contract, diagnostics, source definition, rule package, validator, resolved graph, and candidate draft helper remain covered and passing.

## Notes

- No XcodeGen regeneration was needed for this node because no Swift files were added or moved.
- Existing compile-time note in `RulePackageUseCaseTests` about `#expect(true)` remains unrelated to P3-7.11.
