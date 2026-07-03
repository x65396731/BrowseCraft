# BrowseCraft P2-6.1 URL Builder Unit Tests Run 1

- Date: 2026-07-04
- Scope: P2-6.1 SearchRule / URLTemplate URL builder.
- Destination: `platform=iOS Simulator,name=iPhone 17 Pro`
- Xcode: `/Applications/Xcode.app/Contents/Developer`

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/URLTemplateModelTests
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests
```

## Result

- Targeted URLTemplateModelTests: passed.
- BrowseCraftTests full target: passed, 84 tests in 18 suites, 0 failures.

## Notes

- Initial target run passed but only discovered the two existing `URLTemplateModelTests` entries. The new URL builder checks were therefore folded into those existing test entries as helper assertions, then the targeted test was rerun successfully.
- The URL builder assertions cover legacy search URL rendering, structured `searchTemplate`, `{page:start:step}` pagination values, and `{urlQuery:name}` fallback default behavior.

## xcresult

- Targeted rerun: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_01-11-33-+0900.xcresult`
- Full target rerun: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_01-11-51-+0900.xcresult`
