# BrowseCraft P5.1.20 Commit Cleanup - Run 1

- Date: 2026-07-07
- Scope: final cleanup verification for P5.1.17 through P5.1.19 before committing Core and App changes.

## Commands

```sh
swift test --filter SourceRuntimeHelperTests
```

- Workdir: `/Users/trs/BrowseCraftCore`

```sh
xcodebuild -quiet -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceImportDebugSnapshotTests -only-testing:BrowseCraftTests/VideoTabDiscoveryTests -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests test
```

- Workdir: `/Users/trs/BrowseCraft`

## Result

- Core `SourceRuntimeHelperTests`: passed, 16 tests, 0 failures.
- App related video regression: passed with exit code 0.

## Notes

- Core covers the backward-compatible `SourceDebugSnapshot` field expansion.
- App covers video import debug snapshots, user-facing aggregate import messages, invalid URL no-save behavior, `needsReview` no-save behavior, and saved source `loadList` validation.
- Existing third-party warnings from Pods and an asset catalog trait lookup warning appeared during App tests; no P5.1.20 failures.
