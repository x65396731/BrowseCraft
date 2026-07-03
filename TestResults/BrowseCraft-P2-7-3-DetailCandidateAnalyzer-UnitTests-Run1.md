# BrowseCraft P2-7.3 Detail Candidate Analyzer Unit Tests Run 1

Date: 2026-07-04

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SwiftSoupRuleCandidateAnalyzerTests
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests
```

## Result

- Targeted `SwiftSoupRuleCandidateAnalyzerTests`: passed.
- Targeted suite count: 1 suite.
- Targeted test count: 2 tests.
- Full `BrowseCraftTests`: passed.
- Full suite count: 19 suites.
- Full test count: 86 tests.
- Failures: 0.

## Coverage Focus

- List candidate analyzer still recommends item and field candidates.
- Detail candidate analyzer recommends chapter container, chapter item, chapter title, and chapter link candidates.
- Detail candidate analyzer avoids nav, recommendation, related, and language-area chapter-like links.

## Notes

- `xcodegen generate` was not rerun for this test pass because P2-7.3 only modified files already introduced in P2-7.2.
- Xcode emitted non-fatal Swift warnings for redundant `try` expressions in `SwiftSoupRuleCandidateAnalyzer`.
- `.xcresult` bundles are intentionally not committed; this Markdown file preserves the relevant result summary.

## Result Bundles

- Targeted: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_02-19-58-+0900.xcresult`
- Full: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_02-20-15-+0900.xcresult`
