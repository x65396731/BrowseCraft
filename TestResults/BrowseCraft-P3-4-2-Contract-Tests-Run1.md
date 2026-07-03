# BrowseCraft P3-4.2 Contract Tests Run 1

- Date: 2026-07-04
- Scope: P3-4.1 capabilities and P3-4.2 runtime context/request intent

## Commands

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Run from:

```text
/Users/xiefei/Desktop/BrowseCraftCore
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests
```

Run from:

```text
/Users/xiefei/Desktop/test-git
```

## Result

- BrowseCraftCore: passed, 12 tests, 0 failures.
- BrowseCraftTests: passed, 102 tests in 20 suites, 0 failures.

## Notes

- Core tests covered capability limitations, context operation/section handoff, and request intent Codable/Hashable behavior.
- App regression confirmed `SourceRuntimeInputBridge` and `RuleSourceRuntimeAdapter` compile with section role string bridging and the existing P2 rule/parser tests continue passing.

## xcresult

```text
/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dpkvwvzprjvrsuazgcmajvkpjgkg/Logs/Test/Test-BrowseCraft-2026.07.04_08-26-04-+0900.xcresult
```
