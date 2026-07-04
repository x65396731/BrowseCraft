# BrowseCraft P3-7.8 Runtime Behavior Tests Run 1

- Date: 2026-07-04
- Scope: P3-7.8 runtime unsupported/diagnostics and runtime behavior test reinforcement.
- Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SourceRuntimeMappingTests -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -derivedDataPath /private/tmp/BrowseCraft-P3-7-8-Test-DerivedData -resultBundlePath /private/tmp/BrowseCraft-P3-7-8-Run2.xcresult`
- Result: Passed.
- Suites:
  - `RequestConfigUseCaseTests`: 13 tests passed.
  - `SourceRuntimeMappingTests`: 5 tests passed.
- Total: 18 tests passed, 0 failures.
- Notes:
  - Run 1 failed at compile time due to a new test helper argument-order mistake before any tests executed.
  - Run 2 fixed the test code and passed.
  - Coverage added for `RefreshSourceRuntimeUseCase` context construction, `RuleSourceRuntimeAdapter` source mismatch, list URL override rejection, search header override rejection, ruleID tab selection, debug skipped diagnostics context, and existing Library runtime refresh behavior.
  - Result bundle: `/private/tmp/BrowseCraft-P3-7-8-Run2.xcresult`.
