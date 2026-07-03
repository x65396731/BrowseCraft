# BrowseCraft P3-2 Global Unit Tests Run 1

- Date: 2026-07-04
- Scope: P3-2 App-layer `RuleSourceRuntimeAdapter` MVP global unit regression
- Command:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -workspace /Users/xiefei/Desktop/test-git/BrowseCraft.xcworkspace \
    -scheme BrowseCraft \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:BrowseCraftTests
  ```
- Result: Passed
- Summary: 102 tests in 20 suites passed, 0 failures.
- Source packages resolved:
  - `BrowseCraftCore`: `/Users/xiefei/Desktop/BrowseCraftCore`
  - `BrowseCraftRulesKit`: `git@github.com:x65396731/BrowseCraftRulesKit.git @ main (cfcbd75)`
- Notes:
  - Confirms P3-2 App-side runtime adapter changes compile with the app target.
  - Existing unit coverage for rule parsing, rule package, rule debug, candidate draft application, V2 rules, request config, and source management still passes.
  - UI tests were not run.
- `.xcresult` path:
  `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dpkvwvzprjvrsuazgcmajvkpjgkg/Logs/Test/Test-BrowseCraft-2026.07.04_07-57-26-+0900.xcresult`
