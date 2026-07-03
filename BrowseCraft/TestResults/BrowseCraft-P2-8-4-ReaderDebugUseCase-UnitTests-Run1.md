# BrowseCraft P2-8.4 Reader Debug UseCase Unit Tests Run 1

- Date: 2026-07-04
- Device: iPhone 17 Pro Simulator, iOS 26.5
- Environment: BrowseCraft, macOS 26.5.1
- Result: Passed

## Scope

P2-8.4 adds `ReaderDebugUseCase` and extends `RuleDebugPreviewItem` with `imageURL` for image previews.

The focused tests cover:

- Reader Debug successful request path.
- Resolved reader context request usage.
- Explicit `GalleryRule` parser entry.
- List context handoff into reader parsing.
- WebView and auto-scroll request summary.
- Image preview output through `RuleDebugSession.previewItems`.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RuleDebugUseCaseTests -resultBundlePath /private/tmp/BrowseCraft-P2-8-4-ReaderDebugUseCase.xcresult
```

- Result: Passed
- Total tests: 7
- Passed tests: 7
- Failed tests: 0
- Skipped tests: 0
- Result bundle: `/private/tmp/BrowseCraft-P2-8-4-ReaderDebugUseCase.xcresult`

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests -resultBundlePath /private/tmp/BrowseCraft-P2-8-4-Full.xcresult
```

- Result: Passed
- Total tests: 93
- Passed tests: 93
- Failed tests: 0
- Skipped tests: 0
- Result bundle: `/private/tmp/BrowseCraft-P2-8-4-Full.xcresult`

## Notes

- No `xcodegen generate` was needed for this run.
- No `BrowseCraft.xcodeproj/project.pbxproj` change was produced by this run.
- `.xcresult` bundles are temporary local artifacts; this Markdown file is the retained test record.
