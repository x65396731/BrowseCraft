# BrowseCraft P5.1.30a-3 ARTE RulesKit Catalog Run 1

- Date: 2026-07-08
- Scope: Add ARTE WebView genericHTML video sample to BrowseCraftRulesKit catalog.
- RulesKit source: `/Users/trs/BrowseCraftRulesKit/Sources/BrowseCraftRulesKit/BrowseCraftPrivateRuleCatalog.swift`

## Commands

```sh
cd /Users/trs/BrowseCraftRulesKit
swift test
cd /Users/trs/BrowseCraft
xcodegen generate
env -u GEM_HOME -u GEM_PATH pod install
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Result

- BrowseCraftRulesKit tests: passed.
- BrowseCraft build: passed.

## Notes

- Added `catalog.video.arte` with `adapter = genericHTML`.
- The rule uses `sharedRequest.needsWebView = true` and `sharedRequest.autoScroll = true`.
- Entry URL is `https://www.arte.tv/en/videos/`.
- This catalog entry currently covers the list-stage WebView rendered DOM sample; detail/play samples remain a follow-up item.
- Existing app build warnings remain unrelated: duplicate simulator destination, Metal toolchain search path, and FFmpegKit patch script dependency-analysis note.
