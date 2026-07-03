# BrowseCraft P2-8.2 Detail Debug UseCase Unit Tests Run 1

- Date: 2026-07-04
- Device: iPhone 17 Pro Simulator, iOS 26.5
- Environment: BrowseCraft, macOS 26.5.1
- Result: Passed

## Scope

P2-8.2 adds `DetailDebugUseCase` and extends `RuleDebugPreviewItem` with `chapterURL` for chapter previews.

The focused tests cover:

- Detail Debug successful request path.
- Resolved detail context request usage.
- Explicit `DetailRule` parser entry.
- List context handoff into detail parsing.
- Chapter preview output through `RuleDebugSession.previewItems`.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RuleDebugUseCaseTests -resultBundlePath /private/tmp/BrowseCraft-P2-8-2-DetailDebugUseCase.xcresult
```

- Result: Passed
- Total tests: 6
- Passed tests: 6
- Failed tests: 0
- Skipped tests: 0
- Result bundle: `/private/tmp/BrowseCraft-P2-8-2-DetailDebugUseCase.xcresult`

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests -resultBundlePath /private/tmp/BrowseCraft-P2-8-2-Full.xcresult
```

- Result: Passed
- Total tests: 92
- Passed tests: 92
- Failed tests: 0
- Skipped tests: 0
- Result bundle: `/private/tmp/BrowseCraft-P2-8-2-Full.xcresult`

## Notes

- No `xcodegen generate` was needed for this run.
- No `BrowseCraft.xcodeproj/project.pbxproj` change was produced by this run.
- `.xcresult` bundles are temporary local artifacts; this Markdown file is the retained test record.
