# BrowseCraft P4.8 Entry-Driven Source Import Run 1

- Date: 2026-07-05
- Scope: P4.8 entry-driven Add Source adjustment.
- Command:
  - `xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/BrowseCraftDerivedData-P4-8-entry -resultBundlePath /private/tmp/BrowseCraft-P4-8-Entry-Driven-Run2.xcresult -only-testing:BrowseCraftTests/SourceImportRecommendationTests -only-testing:BrowseCraftTests/SourceImportRecommendationUseCaseTests`
- Result: passed.
- Swift Testing: 10 tests passed, 0 failures.
- Covered suites:
  - `SourceImportRecommendationTests`
  - `SourceImportRecommendationUseCaseTests`
- Notes:
  - The first sandboxed `xcodebuild` attempt failed because CoreSimulator services were unavailable in the sandbox.
  - The first elevated retry reused the failed result bundle path and failed before running tests.
  - The successful run used `/tmp/BrowseCraft-P4-8-Entry-Driven-Run2.xcresult`.
