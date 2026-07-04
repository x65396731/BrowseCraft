# BrowseCraft P3-7.5 Runtime Mapping Tests Run 1

- Date: 2026-07-04
- Scope: P3-7.5 Bridge naming/design debt cleanup.
- Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SourceRuntimeMappingTests -only-testing:BrowseCraftTests/RuleDebugSourceMappingTests -derivedDataPath /private/tmp/BrowseCraft-P3-7-5-Test-DerivedData-Run2 -resultBundlePath /private/tmp/BrowseCraft-P3-7-5-Run2.xcresult`
- Result: Passed.
- Suites:
  - `RuleDebugSourceMappingTests`: 5 tests passed.
  - `SourceRuntimeMappingTests`: 4 tests passed.
- Total: 9 tests passed, 0 failures.
- Notes:
  - The first sandboxed run failed before testing because CoreSimulator was unavailable inside the sandbox.
  - The successful run used the normal Xcode/CoreSimulator environment.
  - Result bundle: `/private/tmp/BrowseCraft-P3-7-5-Run2.xcresult`.
