# BrowseCraft P2-7.4 Reader Candidate Analyzer Unit Tests Run 1

Date: 2026-07-04

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SwiftSoupRuleCandidateAnalyzerTests
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests
```

## Result

- First targeted run failed.
- Failure: `readerAnalyzerRecommendsPageImagesWithoutAdOrAvatarNoise` produced no image candidate.
- Cause: reader noise filtering matched the substring `ad`; the word `reader` contains `ad`, so real reader page images were incorrectly filtered as ad content.
- Fix: narrowed `ad` and `ads` matching to token boundaries, while keeping broad matching for explicit markers such as `advert`, `avatar`, `banner`, `logo`, `related`, and `comment`.
- Second targeted `SwiftSoupRuleCandidateAnalyzerTests`: passed.
- Targeted suite count: 1 suite.
- Targeted test count: 3 tests.
- Full `BrowseCraftTests`: passed.
- Full suite count: 19 suites.
- Full test count: 87 tests.
- Failures after fix: 0.

## Coverage Focus

- List candidate analyzer still recommends item and field candidates.
- Detail candidate analyzer still avoids recommendation and language-area chapter noise.
- Reader candidate analyzer recommends page image selectors and image URL attributes.
- Reader candidate analyzer avoids ad, avatar, logo, related thumbnail, and comment-area image noise.
- Regression coverage added for the `reader` versus `ad` substring false positive.

## Notes

- `xcodegen generate` was not rerun for this test pass because P2-7.4 only modified files already introduced in P2-7.2.
- Xcode emitted non-fatal Swift warnings for redundant `try` expressions in `SwiftSoupRuleCandidateAnalyzer`.
- Simulator emitted non-fatal duplicate accessibility class diagnostics during test execution.
- `.xcresult` bundles are intentionally not committed; this Markdown file preserves the relevant result summary.

## Result Bundles

- First targeted failed run: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_02-26-01-+0900.xcresult`
- Second targeted passed run: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_02-26-32-+0900.xcresult`
- Full passed run: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_02-26-48-+0900.xcresult`
