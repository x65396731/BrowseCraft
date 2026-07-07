# BrowseCraft P5.1.16 SourceContentNoiseFilter - Run 1

Date: 2026-07-07 12:31:29 +0900

## Scope

Implemented the first shared content noise filtering layer for source runtimes, with video runtime as the first integration point.

## Changes Covered

- Added `SourceContentNoiseFilter` and supporting candidate/decision/reason models under `Application/Runtime/Source/Filtering`.
- Integrated the filter into `GenericHTMLVideoHTMLMapper` list item parsing.
- Integrated the filter into GenericHTML iframe/embed playback candidate selection so tracking frames can be skipped before a real playback iframe.
- Left comic and RSS runtime behavior unchanged; the model is prepared for later reuse.

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild test -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SourceContentNoiseFilterTests -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests -only-testing:BrowseCraftTests/VideoRuntimeMacCMSMappingTests
```

## Result

Passed.

- Test suites: 3
- Tests: 23
- Failures: 0

## Notes

- First sandboxed xcodebuild attempt failed because CoreSimulator access was blocked; the same command passed after rerunning with approved external xcodebuild access.
- An initial implementation treated a list item URL host containing `video` as playback signal; this was corrected so list/navigation candidates only inspect URL path for playback markers.
- `git diff --check` passed before the successful test run.

## xcresult

`/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-ekyodtkldclxfmcsueisismacgpi/Logs/Test/Test-BrowseCraft-2026.07.07_12-33-12-+0900.xcresult`
