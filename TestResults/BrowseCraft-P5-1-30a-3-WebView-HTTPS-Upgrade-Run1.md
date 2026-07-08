# BrowseCraft P5.1.30a-3 WebView HTTPS Upgrade Run 1

- Date: 2026-07-08
- Scope: Fix ARTE WebView rendered DOM failure caused by an HTTP main-frame navigation blocked by ATS.

## Failure Signal

Runtime log showed `WKWebView` rendering `https://www.arte.tv/en/videos/`, then failing provisional navigation for `http://www.arte.tv/en/`:

```text
NSURLErrorDomain Code=-1022
The resource could not be loaded because the App Transport Security policy requires the use of a secure connection.
```

## Change

- `WKWebViewHTMLLoader` now upgrades main-frame `http://` navigation actions to matching `https://` URLs.
- The fix does not relax ATS and does not affect the static HTTP loader.

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Result

- Build: passed.

## Notes

- Existing warnings remain unrelated: duplicate simulator destination, Metal toolchain search path, and FFmpegKit patch script dependency-analysis note.
