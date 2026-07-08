# BrowseCraft P5.1.30a WebView needsWebView - Run 1

Date: 2026-07-08

## Scope

- Strengthened video runtime `needsWebView` handling after P5.1.30a-0 architecture cleanup.
- `VideoHTMLRenderGuard` now validates WebView-rendered DOM:
  - emits `video.webViewRenderedDOMUsed` when rendered DOM enters content mapping
  - rejects empty rendered HTML as `video.renderedHTMLEmpty`
  - rejects WebView output that still looks like a JS shell as `video.renderedHTMLStillShell`
  - emits account / anti-bot issues when rendered DOM still contains those markers
- Video list/detail/play loaders now merge render issues into runtime diagnostics.
- Added tests for stage-level `needsWebView` on list/detail/play and runtime override behavior.

## Verification

1. `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests test`
2. `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests -only-testing:BrowseCraftTests/VideoRuntimeMacCMSMappingTests -only-testing:BrowseCraftTests/VideoSourceDetectionTests test`
3. `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

## Result

- Targeted needsWebView tests: passed.
- Video runtime regression tests: passed.
- Build: passed.
- Notes:
  - Existing Metal toolchain search path warning remains.
  - Existing `Patch FFmpegKit Bundle Identifiers` always-run script note remains.
