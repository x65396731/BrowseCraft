# BrowseCraft P3-5.2 Debug Bridge Tests Run 1

- Date: 2026-07-04
- Scope: P3-5.2 Core debug summary models and App debug bridge.
- Core command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- App command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests`

## Result

- Core: passed, 15 XCTest tests, 0 failures.
- App: passed, 110 tests in 22 suites, 0 failures.

## Coverage Notes

- `SourceDebugSnapshot` and nested debug summary models Codable/Hashable behavior.
- `RuleDebugSession` to `SourceDebugSnapshot` bridge.
- Request summary, response summary, extraction log, preview item, issue severity/category/field mapping.
- Existing P2/P3 parser, package, runtime, candidate, and rule graph regression tests remained green.

## Local Artifacts

- `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dpkvwvzprjvrsuazgcmajvkpjgkg/Logs/Test/Test-BrowseCraft-2026.07.04_09-41-07-+0900.xcresult`
- The `.xcresult` bundle is an ignored local artifact; this Markdown file is the retained test summary.
