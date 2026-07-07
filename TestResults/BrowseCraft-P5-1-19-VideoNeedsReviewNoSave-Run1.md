# BrowseCraft P5.1.19 Video NeedsReview No Save - Run 1

- Date: 2026-07-07
- Scope: video import save boundary after removing the user-facing `needsReview` save path.

## Commands

```sh
xcodebuild -quiet -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceImportDebugSnapshotTests -only-testing:BrowseCraftTests/VideoTabDiscoveryTests test
```

```sh
xcodebuild -quiet -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceImportDebugSnapshotTests -only-testing:BrowseCraftTests/VideoTabDiscoveryTests -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests test
```

## Result

- Status: Passed.
- First targeted run: passed with exit code 0.
- Related video regression run: passed with exit code 0.

## Notes

- `needsReview` remains an internal import/debug decision, but the video import UI no longer exposes `Save Anyway`.
- `SourcesViewModel.saveReviewedVideoSource` and `AddVideoSourceUseCase.saveReviewedSource` were removed.
- `needsReview` user-facing copy now explains that the website needs further analysis and cannot be added right now.
- Supported/high-confidence video sources still save and can load a list through `VideoSourceRuntime.loadList`.
- Test output included existing dependency warnings from Pods and asset catalog trait lookup; no P5.1.19 failures.
