# BrowseCraft P3-5.4 Schema Bridge Tests Run 1

- Date: 2026-07-04
- Scope: P3-5.4 Core `BrowseCraftRuleSchema` and App `SiteRule` schema bridge.
- Core command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- App command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests`

## Result

- Core: passed, 17 XCTest tests, 0 failures.
- App: passed, 112 tests in 22 suites, 0 failures.

## Notes

- First App run failed because `SourceRulePrimitiveBridge.swift` used `Data`, `JSONEncoder`, and `JSONDecoder` without importing `Foundation`.
- Added `import Foundation`, then reran App tests successfully.

## Coverage Notes

- `BrowseCraftRuleSchema` decodes legacy + V2 rule shape.
- Core schema covers PageRule entry helpers and RuleSets id lookup.
- `SiteRule.browseCraftRuleSchema()` bridges through the shared JSON shape.
- Existing parser, package, runtime, candidate, draft, request, and resolved graph regression tests remained green.

## Local Artifacts

- Failed `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dpkvwvzprjvrsuazgcmajvkpjgkg/Logs/Test/Test-BrowseCraft-2026.07.04_09-56-42-+0900.xcresult`
- Passing `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dpkvwvzprjvrsuazgcmajvkpjgkg/Logs/Test/Test-BrowseCraft-2026.07.04_09-57-10-+0900.xcresult`
- The `.xcresult` bundles are ignored local artifacts; this Markdown file is the retained test summary.
