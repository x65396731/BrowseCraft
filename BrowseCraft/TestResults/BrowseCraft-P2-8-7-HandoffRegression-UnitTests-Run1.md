# BrowseCraft P2-8.7 Handoff Regression Unit Tests Run 1

- Date: 2026-07-04
- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Destination: `platform=iOS Simulator,name=iPhone 17 Pro`
- RulesKit package: `BrowseCraftRulesKit @ main (cfcbd75)`

## Scope

- P2-8.7 target: `RuleDebugUseCaseTests`
- Regression: full `BrowseCraftTests`
- No UI automation was run.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/RuleDebugUseCaseTests \
  -resultBundlePath /private/tmp/BrowseCraft-P2-8-7-RuleDebugUseCaseTests.xcresult
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests \
  -resultBundlePath /private/tmp/BrowseCraft-P2-8-7-Full-BrowseCraftTests.xcresult
```

## Result

- `RuleDebugUseCaseTests`: passed, 8 tests in 1 suite, 0 failures.
- `BrowseCraftTests`: passed, 94 tests in 19 suites, 0 failures.

## Notes

- New P2-8.7 coverage: `debugUseCasesPreserveListDetailReaderPreviewHandoff`.
- The new test verifies the handoff chain: `List preview detailURL -> Detail preview chapterURL -> Reader preview imageURL`.
- It also verifies `ListContext` survives the handoff through Detail and Reader debug.
- `.xcresult` bundles are local artifacts under `/private/tmp` and are not committed.
