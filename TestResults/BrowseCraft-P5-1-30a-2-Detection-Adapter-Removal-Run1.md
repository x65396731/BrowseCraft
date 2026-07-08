# BrowseCraft P5.1.30a-2 Detection Adapter Removal - Run 1

Date: 2026-07-08

## Scope

- Removed import/detection-stage selection of `macCMS` vs `genericHTML` as the content mapper answer.
- Kept detection focused on facts: WebView-rendered DOM requirement, playback mode, plugin/restriction signals, and no-video-signal diagnostics.
- Kept manual/debug mapper selection as the source of truth for `macCMS` / `genericHTML`.

## Verification

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/VideoRuntimeMacCMSMappingTests -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests test
```

Result: Passed.

## Notes

- Initial sandboxed test attempt failed because CoreSimulator access was blocked; reran with approval.
- Existing warnings remained: duplicate simulator destination, Metal toolchain search path warning, and the always-run FFmpegKit patch script note.
