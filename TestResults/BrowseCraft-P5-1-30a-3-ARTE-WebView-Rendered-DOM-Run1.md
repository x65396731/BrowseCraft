# BrowseCraft P5.1.30a-3 ARTE WebView Rendered DOM Run 1

- Date: 2026-07-08
- Scope: Real non-adult WebView-rendered DOM sample wiring for video genericHTML runtime.
- Sample: `https://www.arte.tv/en/videos/`
- Fixture: `BrowseCraftTests/Fixtures/Video/GenericHTML/arte-rendered-list.html`

## Commands

```sh
xcodegen generate
env -u GEM_HOME -u GEM_PATH pod install
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests -only-testing:BrowseCraftTests/VideoSourceDetectionTests test
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Result

- Targeted tests: passed.
- Build: passed.

## Notes

- `GenericHTMLVideoContentMapper` now accepts modern rendered card structures with `/videos/` routes and `data-testid` card markers.
- `VideoSourceDetector` now treats a Next/SPA marker as WebView-required only when no mappable video content is present, so rendered DOM with video cards is not rejected as a shell.
- The ARTE fixture is a trimmed rendered-DOM sample, not a full archived external page.
- Existing build warnings remain unrelated: duplicate simulator destination, third-party Sendable warnings, Metal toolchain search path warning, and the FFmpegKit patch script dependency-analysis note.
