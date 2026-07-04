# BrowseCraft P3-5.3 Candidate Bridge Tests Run 1

- Date: 2026-07-04
- Scope: P3-5.3 Core candidate report models and App candidate bridge.
- Core command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- App command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests`

## Result

- Core: passed, 16 XCTest tests, 0 failures.
- App: passed, 111 tests in 22 suites, 0 failures.

## Coverage Notes

- `SourceRuleCandidateReport` and nested candidate summary/score/evidence/warning models Codable/Hashable behavior.
- Candidate score clamping remains stable at the Core contract boundary.
- `RuleCandidateReport` to `SourceRuleCandidateReport` bridge.
- Field, stage/operation, selector kind, extract function, confidence, warning, source, evidence, and summary mapping.
- Existing candidate analyzer, draft applier, parser, package, runtime, and rule graph regression tests remained green.

## Local Artifacts

- `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dpkvwvzprjvrsuazgcmajvkpjgkg/Logs/Test/Test-BrowseCraft-2026.07.04_09-48-19-+0900.xcresult`
- The `.xcresult` bundle is an ignored local artifact; this Markdown file is the retained test summary.
