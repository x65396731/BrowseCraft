# BrowseCraft P3-3 Helper Tests Run 1

- Date: 2026-07-04
- Scope: P3-3.1 to P3-3.5 runtime/helper extraction

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

- BrowseCraftCore: passed, 10 tests, 0 failures.
- BrowseCraftTests: passed, 102 tests in 20 suites, 0 failures.

## Notes

- First Core test run with the default CommandLineTools `swift test` failed before compilation because the Package manifest linked against a mismatched CLT SwiftPM library. Re-running with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` fixed the toolchain issue.
- First Xcode toolchain Core test run found that `URL(string: "not a url")` creates a relative URL instead of nil. `SourcePagination.next(nextPageURLString:nextPage:)` now accepts only absolute URLs with scheme and host, while still preserving `nextPage` when the URL string is invalid.
- App regression confirmed `RulePackageUseCases` still passes encode/decode, checksum, import validation, and built-in export behavior after switching to `StableJSONCoding`.

## xcresult

```text
/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dpkvwvzprjvrsuazgcmajvkpjgkg/Logs/Test/Test-BrowseCraft-2026.07.04_08-13-50-+0900.xcresult
```
