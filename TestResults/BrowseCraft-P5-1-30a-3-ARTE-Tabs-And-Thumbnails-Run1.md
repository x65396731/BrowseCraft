# BrowseCraft P5.1.30a-3 ARTE Tabs And Thumbnails Run 1

Date: 2026-07-08

## Scope

- Fixed existing catalog source upgrade so already-imported ARTE sources receive the latest RulesKit definition.
- Added fixed ARTE video tabs as a non-network fallback.
- Kept WebView rendered DOM tab discovery in the catalog import/re-import path.
- Verified ARTE image request config is carried by the upgraded video source definition.

## Commands

- `swift test` in `/Users/trs/BrowseCraftRulesKit`
- `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -skipPackageUpdates -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:BrowseCraftTests/SyncBuiltInSourcesUseCaseTests -only-testing:BrowseCraftTests/SourceRuntimeMappingTests test`
- `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -skipPackageUpdates -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination "platform=iOS Simulator,name=iPhone 17 Pro" build`
- `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -skipPackageUpdates -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:BrowseCraftTests/SyncBuiltInSourcesUseCaseTests test`

## Result

- RulesKit tests passed: 4 tests.
- App targeted tests passed after rerunning with Xcode 26 and `-skipPackageUpdates`.
- Full app build passed.

## Notes

- Default `xcodebuild` points at Xcode 16.1 and cannot resolve the current Swift tools 6.2 `webui` dependency. Verification used Xcode 26.0.1.
- One parallel test/build attempt failed with Xcode build database locking; rerunning the test alone passed.
- Recurring non-blocking warnings remained: duplicate simulator destination, Metal toolchain search path, and existing redundant `#require` warnings in unrelated tests.
