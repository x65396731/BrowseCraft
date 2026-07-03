# BrowseCraft P2-7.2 CandidateAnalyzer Unit Tests - Run 1

- Date: 2026-07-04
- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Simulator: `iPhone 17 Pro`
- Scheme: `BrowseCraft`

## Setup

Commands:

```sh
xcodegen generate
env -u GEM_HOME -u GEM_PATH pod install
```

Reason:

- P2-7.1/P2-7.2 added new Swift files.
- BrowseCraft uses XcodeGen, so the local generated project had to be refreshed before xcodebuild could compile and discover the new test.
- `pod install` was run immediately after `xcodegen generate` to restore CocoaPods integration.

## Targeted Test

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/SwiftSoupRuleCandidateAnalyzerTests
```

Result:

- Passed: 1 test in 1 suite
- Failed: 0
- `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_02-07-50-+0900.xcresult`

Coverage notes:

- Verifies list CandidateAnalyzer recommends `article.card` as item selector.
- Verifies title/link/cover/latestText candidates and sample values.
- Verifies missing cover warning is reported when one item lacks an image.

## Full Unit Regression

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests
```

Result:

- Passed: 85 tests in 19 suites
- Failed: 0
- `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_02-08-17-+0900.xcresult`

Notes:

- No UI tests were run.
- Generated `BrowseCraft.xcodeproj/project.pbxproj` is local XcodeGen output and must not be committed.
