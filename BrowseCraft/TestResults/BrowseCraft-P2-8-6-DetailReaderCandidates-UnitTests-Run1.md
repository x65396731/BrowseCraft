# BrowseCraft P2-8.6 Detail/Reader Candidates Unit Tests Run 1

- Date: 2026-07-04
- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Destination: `platform=iOS Simulator,name=iPhone 17 Pro`
- RulesKit package: `BrowseCraftRulesKit @ main (cfcbd75)`

## Scope

- P2-8.6 target: `RuleDebugUseCaseTests`
- Regression: full `BrowseCraftTests`
- No UI automation was run.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/RuleDebugUseCaseTests \
  -resultBundlePath /private/tmp/BrowseCraft-P2-8-6-RuleDebugUseCaseTests.xcresult
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests \
  -resultBundlePath /private/tmp/BrowseCraft-P2-8-6-Full-BrowseCraftTests.xcresult
```

## Result

- `RuleDebugUseCaseTests`: passed, 7 tests in 1 suite, 0 failures.
- `BrowseCraftTests`: passed, 93 tests in 19 suites, 0 failures.

## Notes

- Initial attempt with `/Applications/Xcode-26.0.1.app/Contents/Developer` failed because that Xcode path does not exist on this machine.
- P2-8.6 coverage confirms Detail Debug attaches `analyzeDetail` candidate reports and Reader Debug attaches `analyzeReader` candidate reports.
- Candidate generation remains non-blocking: analyzer failure path appends a warning issue rather than failing the debug session.
- `.xcresult` bundles are local artifacts under `/private/tmp` and are not committed.
