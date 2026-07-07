# BrowseCraft P5.1.17 SourceDebugSnapshot - Run 1

Date: 2026-07-07

## Scope

- Extended `BrowseCraftCore` `SourceDebugSnapshot` with generic source kind, structure summary, import decision, and signal fields.
- Added backward-compatible decoding for snapshots created before these fields existed.
- Added video import debug snapshot generation through `AddVideoSourceUseCase.executeWithDebugSnapshot`.
- Kept the existing `AddVideoSourceUseCase.execute` return value unchanged for current UI compatibility.

## Verification

```sh
swift test --filter SourceRuntimeHelperTests
```

- Workdir: `/Users/trs/BrowseCraftCore`
- Result: passed
- Count: 16 tests, 0 failures

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild test -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceImportDebugSnapshotTests -only-testing:BrowseCraftTests/VideoTabDiscoveryTests -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/RuleDebugSourceMappingTests
```

- Result: passed
- Count: 37 Swift Testing tests, 0 failures
- `.xcresult`: `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-ekyodtkldclxfmcsueisismacgpi/Logs/Test/Test-BrowseCraft-2026.07.07_12-47-58-+0900.xcresult`

## Notes

- The first `xcodebuild` output also included `Executed 0 tests` from the XCTest runner, followed by the actual Swift Testing run; the Swift Testing suites completed successfully.
- P5.1.17 intentionally keeps Debug UI unchanged. The new entry point is data-layer only.
