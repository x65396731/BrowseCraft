# BrowseCraft P5.1.30a-3 WebView HTTPS Upgrade Run2

- Date: 2026-07-08
- Scope: ARTE WebView rendered DOM catalog import failure after HTTPS upgrade handling
- Result: Build passed

## Failure Input

User runtime log showed:

- `BrowseCraftWebView render html url=https://www.arte.tv/en/videos/ scope=default autoScroll=true`
- `WebPageProxy::didFailProvisionalLoadForFrame ... domain=WebKitErrorDomain, code=102`
- `BrowseCraftRuleTrace stage=list event=catalog-source-add-error message=フレームの読み込みが中断しました。`

## Diagnosis

The previous ARTE fix upgrades main-frame `http` navigations to `https` in `WKNavigationDelegate`.
That implementation intentionally cancels the original insecure navigation with `decisionHandler(.cancel)`.
WebKit reports this intentional cancellation as `WebKitErrorDomain` code `102`, which the loader was still treating as a real list-load failure.

## Fix

- `WKWebViewHTMLLoader` now tracks active HTTPS upgrade navigation with `isLoadingHTTPSUpgrade`.
- During that upgrade only, the loader ignores:
  - `WebKitErrorDomain` code `102`
  - `NSURLErrorDomain` `NSURLErrorCancelled`
- The ignore path is limited to the upgrade window so unrelated WebView failures still surface.

## Verification

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Outcome:

- Passed
- Non-blocking simulator/Xcode warnings observed:
  - duplicate matching simulator destination
  - Metal toolchain search path warning
  - script phase dependency-analysis note
