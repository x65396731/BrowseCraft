# BrowseCraft P5.1.15 VideoDetectionLexicon Cleanup - Run 1

Date: 2026-07-07 12:00:40 +0900

## Scope

Cleaned remaining video runtime semantic keyword checks so detector, tab discovery, generic HTML mapping, and MacCMS mapping share `VideoDetectionLexicon` instead of scattering language-specific markers in mapper/discoverer logic.

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild test -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/VideoTabDiscoveryTests -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests -only-testing:BrowseCraftTests/VideoRuntimeMacCMSMappingTests
```

## Result

Passed.

- Test suites: 4
- Tests: 46
- Failures: 0

## Notes

- `VideoDetectionLexicon` now includes finer-grained categories for CAPTCHA, signing/token, encrypted playback, WASM, session, private API, pay/account restrictions, and navigation rejection markers.
- `GenericHTMLVideoTabDiscoverer`, `GenericHTMLVideoHTMLMapper`, and `MacCMSVideoHTMLMapper` now use the lexicon for semantic marker matching.
- `git diff --check` passed before the test run.

## xcresult

`/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-ekyodtkldclxfmcsueisismacgpi/Logs/Test/Test-BrowseCraft-2026.07.07_11-59-45-+0900.xcresult`
