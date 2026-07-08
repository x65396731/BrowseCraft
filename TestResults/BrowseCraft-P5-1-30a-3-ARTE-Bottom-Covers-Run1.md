# BrowseCraft P5.1.30a-3 ARTE Bottom Covers Run 1

Date: 2026-07-08

## Scope

- Investigated missing covers for the bottom ARTE video list items.
- Added GenericHTML video cover extraction for `data-srcset`, `srcset`, and `source[srcset]`.
- Changed WebView rendered HTML auto-scroll from a single jump to progressive scrolling so lazy-loaded bottom cards can enter the viewport before DOM capture.

## Finding

- The attached log showed 8 ARTE list items.
- Image requests were emitted for the first five covers only.
- The bottom three items had real `arte.tv/en/videos/...` detail URLs and no image request log, which indicates `coverURL == nil` rather than an image request failure.
- Based on URL shape and runtime filtering, these bottom three are not likely ads. The failure mode is missing/lazy cover data in the rendered DOM.

## Commands

- `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -skipPackageUpdates -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests test`
- `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -skipPackageUpdates -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination "platform=iOS Simulator,name=iPhone 17 Pro" build`

## Result

- GenericHTML video mapping tests passed.
- Full app build passed.

## Notes

- One parallel build attempt failed due to Xcode `build.db` locking; rerunning build alone passed.
- Recurring non-blocking warnings remained: duplicate simulator destination, Metal toolchain search path, and script phase dependency note.
