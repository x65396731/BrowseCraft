# BrowseCraftCore P3-8.5b SourceItemReference Tests Run 1

- Date: 2026-07-04
- Scope: P3-8.5b Core tests for Detail/Reader handoff contract.
- Result: Passed.

## Changes Verified

- Added `SourceItemReferenceTests`.
- Verified `SourceItemReference` Codable round trip preserves:
  - `detailURL`
  - `chapterURL`
  - `coverURL`
  - `SourceItemListContext`
  - `SourceRequestOverride`
  - `SourceRuntimeContext`
- Verified normal detail handoff can carry only `detailURL`.
- Verified direct-reader handoff can carry `chapterURL`.
- Verified Hashable/equality distinguishes `.detail` and `.directReader` handoff intents.

## Commands

```sh
swift test
```

```sh
git -C /Users/xiefei/Desktop/BrowseCraftCore diff --check
```

## Result Summary

- Test target: `BrowseCraftCorePackageTests`
- Total tests: 38
- Passed: 38
- Failed: 0
- New suite: `SourceItemReferenceTests`
- New tests: 4

## Notes

- The first sandboxed `swift test` attempt reached old tests but exited with SwiftPM/clang cache permission errors and did not compile the new test file.
- The authorized rerun compiled `SourceItemReferenceTests.swift` and completed successfully.
- No App code was changed for P3-8.5b.
- No XcodeGen or CocoaPods step was needed because this node only changed the local Swift package.
