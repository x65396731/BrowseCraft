# BrowseCraft P2-7.5 Pagination Candidate Analyzer Unit Tests Run 1

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
- Targeted test count: 4 tests.
- Full `BrowseCraftTests`: passed.
- Full suite count: 19 suites.
- Full test count: 88 tests.
- Failures: 0.

## Coverage Focus

- List candidate analyzer still recommends item and field candidates.
- Detail candidate analyzer still avoids recommendation and language-area chapter noise.
- Reader candidate analyzer still recommends page image selectors and avoids ad/avatar noise.
- Pagination candidate analyzer recommends next-page link selectors and page placeholder candidates.
- Pagination candidate analyzer avoids previous/current and related-area pagination-like links.

## Notes

- `xcodegen generate` was not rerun for this test pass because P2-7.5 only modified files already introduced in P2-7.2.
- Xcode emitted non-fatal Swift warnings for redundant `try` expressions in `SwiftSoupRuleCandidateAnalyzer`.
- Simulator emitted non-fatal duplicate accessibility class diagnostics during full test execution.
- `.xcresult` bundles are intentionally not committed; this Markdown file preserves the relevant result summary.

## Result Bundles

- Targeted: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_02-31-31-+0900.xcresult`
- Full: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_02-31-48-+0900.xcresult`
