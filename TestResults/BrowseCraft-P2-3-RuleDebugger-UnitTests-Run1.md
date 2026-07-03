# BrowseCraft P2-3 RuleDebugger Unit Tests Run 1

- Date: 2026-07-03 23:14 +0900
- Command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests`
- Preparation:
  - `xcodegen generate`
  - `env -u GEM_HOME -u GEM_PATH -u RUBYLIB -u RUBYOPT pod install`
- Scope: `BrowseCraftTests`
- Result: Passed
- Summary: 83 tests in 18 suites passed.
- P2-3 suites observed:
  - `RuleDebugRealRuleRegressionTests`: 4 tests passed.
  - `RuleDebugUseCaseTests`: 3 tests passed.
  - `SwiftSoupRuleDebugParserTests`: 1 test passed.
- Initial attempt note: the first test attempt failed at build time after `xcodegen generate` because CocoaPods frameworks were not integrated in the regenerated workspace. Running `pod install` fixed dependency resolution.
- `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.03_23-14-01-+0900.xcresult`
