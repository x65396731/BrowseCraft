# BrowseCraft P3-5.1 Primitive Bridge Tests Run 1

- Date: 2026-07-04
- Scope: P3-5.1 Core public rule primitives and App primitive bridge.
- Core command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- App command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests`
- Preflight: `xcodegen generate`, then `env -u GEM_HOME -u GEM_PATH pod install`

## Result

- Core: passed, 14 XCTest tests, 0 failures.
- App: passed, 109 tests in 22 suites, 0 failures.

## Coverage Notes

- `SourceRuleField`, `SourceRuleSelectorKind`, and `SourceRuleExtractFunction` Codable/Hashable/raw value behavior.
- `RuleDebugStage` to `SourceRuntimeOperation` mapping, including no reverse mapping for `.debug`.
- `RuleDebugField` and `RuleCandidateField` mapping to Core primitive fields.
- `SelectorKind` and `ExtractFunction` round-trip mapping through Core primitive enums.

## Local Artifacts

- `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dpkvwvzprjvrsuazgcmajvkpjgkg/Logs/Test/Test-BrowseCraft-2026.07.04_09-17-08-+0900.xcresult`
- The `.xcresult` bundle is an ignored local artifact; this Markdown file is the retained test summary.
