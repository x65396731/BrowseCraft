# BrowseCraft P5.1.30a-1 WebView Wait Strategy - Run 1

Date: 2026-07-08

## Scope

- Added a fixed WebView render wait strategy without Core schema changes.
- `WKWebViewHTMLLoader` now applies:
  - 12 second internal timeout
  - 500 ms post-`didFinish` delay
  - optional `autoScroll`
  - 500 ms post-scroll delay
  - up to 3 DOM length stability checks before reading `outerHTML`
- Added `WKWebViewHTMLLoaderError.timedOut`.

## Verification

1. `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/PageContentLoaderTests test`
2. `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

## Result

- PageContentLoader tests: passed.
- Build: passed.
- Notes:
  - No Core request schema changes were made.
  - Real website instability is outside this validation scope.
  - Existing Metal toolchain search path warning remains.
  - Existing `Patch FFmpegKit Bundle Identifiers` always-run script note remains.
