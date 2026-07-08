# BrowseCraft P5.1.30a-3 WebUI And ARTE Thumbnails Run1

- Date: 2026-07-08
- Scope: Confirm Web playback physical layer and fix partial ARTE thumbnail failures
- Result: Passed

## Runtime Log Diagnosis

User log showed:

- `openEpisode playback-result ... mediaKind=unknown status=pageOnly`
- repeated ARTE image requests to `https://api-cdn.arte.tv/img/v2/image/.../380x214?type=TEXT`
- repeated WebKit/ImageIO logs: `makeImagePlus ... 'WEBP' ... failed`

`pageOnly` maps to `VideoPlaybackDestination.web`, which uses `VideoWebPlayerView`.
The prior logs did not explicitly name the physical view, so a DEBUG log was added.

## Web Playback Confirmation

`VideoWebPlayerView` now logs:

```text
[BrowseCraftVideoWebPlayer] appear/load url=...
```

When that appears after `status=pageOnly`, the opened player is the WebUI/WKWebView physical layer, not KSPlayer/native.

## Thumbnail Fix

ARTE CDN returns WebP when requested with the app default image Accept header:

```text
content-type: image/webp
```

It returns JPEG when requested with:

```text
Accept: image/jpeg,image/png,image/*;q=0.8,*/*;q=0.5
```

Changes:

- ARTE catalog rule now sets `sharedRequest.imageRequest.headers.Accept` to JPEG/PNG-first.
- Video library presentation now returns video `sharedRequest + listRequest` image config to `CoverImageView`, so video sources can actually use `imageRequest`.

## Verification

Commands:

```sh
swift test
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SourceRuntimeMappingTests -only-testing:BrowseCraftTests/ImageRequestFactoryTests test
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Outcome:

- BrowseCraftRulesKit tests passed.
- Targeted app tests passed.
- App build passed.
- Non-blocking warnings observed:
  - duplicate matching simulator destination
  - Metal toolchain search path warning
  - script phase dependency-analysis note
