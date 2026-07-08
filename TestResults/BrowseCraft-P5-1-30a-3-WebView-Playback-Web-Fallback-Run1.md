# BrowseCraft P5.1.30a-3 WebView Playback Web Fallback Run1

- Date: 2026-07-08
- Scope: ARTE WebView playback destination selection
- Result: Passed

## Runtime Log Diagnosis

User runtime log showed:

- `openEpisode playback-result source=catalog.video.arte ... mediaKind=unknown status=failed(...mediaURLNotFound)`

That means playback did not enter `VideoNativePlayerView` and did not enter `VideoWebPlayerView`.
`VideoPlayerViewModel.playbackDestination` mapped the failed status to the unavailable player state.

## Fix

- `GenericHTMLVideoContentMapper` now returns `status = .pageOnly` when:
  - no direct mp4/m3u8/iframe media URL is exposed
  - the video definition explicitly requires rendered WebView playback via `sharedRequest.needsWebView` or `playRequest.needsWebView`
- Static GenericHTML pages still return `failed(.mediaURLNotFound)` when direct media is missing.

## Expected Player Destination

For ARTE rendered playback pages without exposed direct media:

- native: no
- web: yes
- destination: `VideoWebPlayerView`
- request URL: `reference.candidateMediaURL ?? reference.playPageURL`

## Verification

Commands:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests test
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Outcome:

- Targeted tests passed.
- App build passed.
- Non-blocking warnings observed:
  - duplicate matching simulator destination
  - Metal toolchain search path warning
  - existing Swift Testing `#require` warnings
  - script phase dependency-analysis note
