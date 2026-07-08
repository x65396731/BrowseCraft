# BrowseCraft P5.1.30a-3 WebView Tab Discovery Run1

- Date: 2026-07-08
- Scope: WebView rendered DOM tab discovery, ARTE section tabs, ARTE category-item filtering, WebUI physical player view naming
- Result: Passed

## Changes Verified

- Added `VideoSourceTabDiscoveryUseCase` so video catalog import can discover tabs from the final entry HTML.
- The use case reuses `PageContentLoader`, so `RequestConfig.needsWebView` and `autoScroll` are honored for rendered DOM discovery.
- `AddCatalogSourceUseCase` now merges explicit catalog tabs with discovered tabs before saving video sources.
- Existing catalog video sources are also enriched and saved when catalog import is invoked again, so previously imported ARTE sources do not require manual deletion before tab discovery can be applied.
- `GenericHTMLVideoTabDiscoverer` now recognizes non-root entry subsections such as `/en/videos/series/` as tabs, while excluding concrete video detail IDs.
- `GenericHTMLVideoContentMapper` filters same-entry single-slug section links such as `/en/videos/series/` from list items.
- WebUI playback physical layer is now named `VideoWebUIPlayerView`, parallel to `VideoNativePlayerView`.

## Verification

Commands:

```sh
xcodegen generate
env -u GEM_HOME -u GEM_PATH pod install
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoTabDiscoveryTests -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests test
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Outcome:

- Targeted tests passed.
- App build passed.
- Non-blocking warnings observed:
  - duplicate matching simulator destination
  - Metal toolchain search path warning
  - existing dependency warnings from GRDB/Nuke
  - script phase dependency-analysis note
