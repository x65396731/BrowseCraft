# BrowseCraft P3-5.11 Completeness Tests - Run 1

Date: 2026-07-04

## Scope

- P3-5.11 completeness check after P3-5.1 through P3-5.10 model migration.
- Reviewed whether additional test code was needed against the P3-5.11 acceptance line:
  - Core tests should cover Codable/Hashable, `SiteRule` decode, resolved graph, draft patch, validator, and package codec.
  - App tests should cover import/export, built-in and user rule boundaries, request priority, context handoff, parser integration, and the prior rule validation stack crash path.

## Test Code Added

Added Core-only `SiteRuleTests` because `SiteRule` Codable/Hashable/decode behavior was previously covered mostly through indirect validator/package/resolved graph tests.

New coverage:

- Complete V2 `SiteRule` JSON decode and helper behavior.
- Canonical Codable round trip preserving rule shape.
- `Hashable`/`Equatable` behavior for equal rules in a `Set<SiteRule>`.

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
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests -derivedDataPath /private/tmp/BrowseCraft-P3-5-11-Test-DerivedData -resultBundlePath /private/tmp/BrowseCraft-P3-5-11-App.xcresult
```

Working directory:

```text
/Users/xiefei/BrowseCraft
```

## Results

- `BrowseCraftCore swift test`: passed, 34 tests, 0 failures.
- `BrowseCraftTests`: passed, 101 tests in 22 suites, 0 failures.

## Notes

- First Core test attempt failed because the new test used a nonexistent `StableJSONCoding.encoder(prettyPrinted:)` helper; the test was corrected to use `StableJSONCoding.makeCanonicalEncoder()`.
- The App test run emitted an existing Swift Testing macro note in `RulePackageUseCaseTests.swift` for `#expect(true)` inside a success-path catch guard; it did not fail the run.
- `.xcresult` path: `/private/tmp/BrowseCraft-P3-5-11-App.xcresult`
- DerivedData path: `/private/tmp/BrowseCraft-P3-5-11-Test-DerivedData`
