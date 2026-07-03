# BrowseCraft P2-7 Global Regression Run 1

- Date: 2026-07-04
- Device: iPhone 17 Pro Simulator, iOS 26.5
- Environment: BrowseCraft, macOS 26.5.1
- Result: Passed

## Test Coverage Decision

P2-7.6 needed additional test code. Existing P2-7.2 to P2-7.5 tests covered selector candidate analysis itself, but did not cover the UseCase contract added in P2-7.6: List/Search Debug sessions must attach a merged `candidateReport` after HTML fetch, including list/search candidates and pagination candidates.

Added coverage in `BrowseCraftTests/Application/RuleDebugUseCaseTests.swift`:

- `listDebugUseCaseAttachesCandidateReport`
- `searchDebugUseCaseAttachesCandidateReport`

These tests use a recording `RuleCandidateAnalyzingService` fake to verify analyzer inputs, stage, rule IDs, URL templates, merged candidate fields, summary counts, and that candidate generation does not introduce debug issues on success.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RuleDebugUseCaseTests -resultBundlePath /private/tmp/BrowseCraft-P2-7-RuleDebugUseCase.xcresult
```

- Result: Passed
- Passed tests: 5
- Failed tests: 0
- Skipped tests: 0
- Result bundle: `/private/tmp/BrowseCraft-P2-7-RuleDebugUseCase.xcresult`

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SwiftSoupRuleCandidateAnalyzerTests -resultBundlePath /private/tmp/BrowseCraft-P2-7-CandidateAnalyzer.xcresult
```

- Result: Passed
- Passed tests: 4
- Failed tests: 0
- Skipped tests: 0
- Result bundle: `/private/tmp/BrowseCraft-P2-7-CandidateAnalyzer.xcresult`

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests -resultBundlePath /private/tmp/BrowseCraft-P2-7-Global.xcresult
```

- Result: Passed
- Total tests: 90
- Passed tests: 90
- Failed tests: 0
- Skipped tests: 0
- Result bundle: `/private/tmp/BrowseCraft-P2-7-Global.xcresult`

## Notes

- No `xcodegen generate` was needed for this run.
- No `BrowseCraft.xcodeproj/project.pbxproj` change was produced by this run.
- `.xcresult` bundles are temporary local artifacts; this Markdown file is the retained test record.
