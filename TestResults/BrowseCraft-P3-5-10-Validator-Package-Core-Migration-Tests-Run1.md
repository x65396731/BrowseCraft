# BrowseCraft P3-5.10 Validator / Package Core Migration Tests - Run 1

Date: 2026-07-04

## Scope

- P3-5.10 moves pure rule validation and rule package codec/checksum behavior into `BrowseCraftCore`.
- App remains responsible for repository, import/export use case orchestration, source conflict checks, and UI-facing presentation.
- App pure validator/codec tests were removed after equivalent Core coverage was added; App use case tests remain.

## Environment

- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Xcode version: 26.6 Build 17F113

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Working directory:

```text
/Users/xiefei/BrowseCraftCore
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests -derivedDataPath /private/tmp/BrowseCraft-P3-5-10-Test-DerivedData -resultBundlePath /private/tmp/BrowseCraft-P3-5-10-App.xcresult
```

Working directory:

```text
/Users/xiefei/BrowseCraft
```

## Results

- `BrowseCraftCore swift test`: passed, 31 tests, 0 failures.
- `BrowseCraftTests`: passed, 101 tests in 22 suites, 0 failures.

## Notes

- Core coverage added:
  - `RuleValidatorTests`: complete V2 rule, missing referenced rule, duplicate page IDs, page title/list reference warnings.
  - `RulePackageCodecTests`: encode/decode, checksum mismatch, unsupported kind, unsupported format version.
- App coverage retained:
  - `RuleManagementUseCaseTests`: update/duplicate use case behavior.
  - `RulePackageUseCaseTests`: export/import use case behavior, source conflict boundaries, built-in source import protection.
- The App test run emitted an existing Swift Testing macro note in `RulePackageUseCaseTests.swift` for `#expect(true)` inside a success-path catch guard; it did not fail the run.
- `.xcresult` path: `/private/tmp/BrowseCraft-P3-5-10-App.xcresult`
- DerivedData path: `/private/tmp/BrowseCraft-P3-5-10-Test-DerivedData`
