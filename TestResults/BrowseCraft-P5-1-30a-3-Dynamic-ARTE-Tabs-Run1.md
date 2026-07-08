# BrowseCraft P5.1.30a-3 Dynamic ARTE Tabs Run 1

Date: 2026-07-08

## Scope

- Removed fixed ARTE category tabs from RulesKit.
- Kept only the entry `Videos` tab in the ARTE catalog rule.
- Verified WebView rendered DOM tab discovery can append more than five discovered tabs.
- Verified existing catalog source sync upgrades image request config without injecting fixed ARTE categories.

## Commands

- `swift test` in `/Users/trs/BrowseCraftRulesKit`
- `DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -quiet -skipPackageUpdates -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:BrowseCraftTests/VideoTabDiscoveryTests -only-testing:BrowseCraftTests/SyncBuiltInSourcesUseCaseTests test`

## Result

- RulesKit tests passed: 4 tests.
- App targeted tests passed.

## Notes

- ARTE tab count is not fixed and not capped at five.
- Runtime behavior is `explicit entry tab + WebView rendered DOM discovered tabs`, deduplicated by URL.
- Recurring non-blocking warnings remained: duplicate simulator destination, Metal toolchain search path, and script phase dependency note.
