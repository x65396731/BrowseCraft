# BrowseCraft P5.1.30a-0 Video Runtime Architecture - Run 1

Date: 2026-07-08

## Scope

- Reorganized App video runtime files by architecture axis:
  - `ContentMapping`
  - `Rendering`
  - `Loading`
  - `PlaybackCandidate`
  - `Detection`
  - `Input`
- Renamed video mapper types from HTML/adapter wording to content mapping wording.
- Moved WebView render requirement into rendering layer.
- Treated legacy `.webView` adapter as `genericHTML + needsWebView` on import/catalog paths.
- Kept iframe/embed handling in playback candidate layer.

## Verification

1. `xcodegen generate`
2. `env -u GEM_HOME -u GEM_PATH pod install`
3. `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
4. `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests -only-testing:BrowseCraftTests/VideoRuntimeMacCMSMappingTests -only-testing:BrowseCraftTests/VideoSourceDetectionTests test`

## Result

- Build: passed.
- Targeted video runtime tests: passed.
- Notes:
  - Default Xcode build failed before verification because WebUI requires Swift tools 6.2; reran successfully with Xcode 26.0.1.
  - Existing Metal toolchain search path warning remains.
  - Existing `Patch FFmpegKit Bundle Identifiers` always-run script note remains.
