# BrowseCraft P5.1.21 SourceDetectionLexicon Run 1

Date: 2026-07-07

## Scope

- Added shared `SourceDetectionLexicon` JSON loading for source detection markers.
- Kept `VideoDetectionLexicon` as a video-domain facade over the shared lexicon.
- Moved `SourceContentNoiseFilter` marker checks onto the shared lexicon.
- Added JSON resources for `base`, `en`, `zh-Hans`, and `ja`.
- Verified JSON resources are included in the Xcode target resources after project regeneration.

## Commands

```sh
./scripts/regenerate-project.sh
```

Result: passed. Xcode project regenerated and CocoaPods integration restored.

```sh
xcodebuild -quiet -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SourceDetectionLexiconTests -only-testing:BrowseCraftTests/SourceContentNoiseFilterTests -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/VideoTabDiscoveryTests test
```

Result: passed.

```sh
xcodebuild -quiet -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests -only-testing:BrowseCraftTests/VideoRuntimeMacCMSMappingTests -only-testing:BrowseCraftTests/VideoSourceImportDebugSnapshotTests test
```

Result: passed after injecting the zh-Hans lexicon into the Chinese MacCMS restricted playback test.

## Notes

- Xcode emitted the existing duplicate simulator destination and build number warnings.
- `GenericHTMLVideoHTMLMapper.swift` still emits the existing `try` warning for `element.id().trimmedNonEmpty`; this was not introduced by P5.1.21.
