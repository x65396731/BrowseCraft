# BrowseCraft P2-6.4 Pagination Unit Tests Run 1

- Date: 2026-07-04
- Scope: P2-6.4 Pagination MVP for search/list debug pagination contracts.
- Destination: `platform=iOS Simulator,name=iPhone 17 Pro`
- Xcode: `/Applications/Xcode.app/Contents/Developer`

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests
```

## Result

- Targeted `RequestConfigUseCaseTests`: passed, 7 tests in 1 suite, 0 failures.
- Full `BrowseCraftTests`: passed, 84 tests in 18 suites, 0 failures.

## Notes

- The first full run failed one P2-6.4 assertion because the generic pagination parser contract allowed a relative next-page URL, while `SearchSourceUseCase` returned it without normalizing. The use case and list debug pagination path now normalize extracted next-page URLs against the current request URL.
- Coverage includes `SearchSourceUseCase.executeWithPagination`, next-page link priority over page-placeholder fallback, relative next-page URL normalization, `PaginationRule.maxPages` boundary wiring, and SwiftSoup `PaginationRule.nextPage` extraction from DOM.
- A sandboxed targeted rerun failed before opening the workspace due CoreSimulator permission errors; the same command succeeded with simulator access.
- No `xcodegen generate` or `pod install` was needed for this run because P2-6.4 did not add new source files after the previous project regeneration.

## xcresult

- Initial failing full run: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_01-37-22-+0900.xcresult`
- Targeted passing run: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_01-38-28-+0900.xcresult`
- Full passing run: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_01-38-54-+0900.xcresult`
