# BrowseCraft P3-5.9 Candidate/Draft Core Migration Build & Tests Run 1

- Date: 2026-07-04
- Xcode: `/Applications/Xcode.app/Contents/Developer` (Xcode 26.6 Build 17F113)
- Core package path used by App: `/Users/xiefei/Desktop/BrowseCraftCore` -> `/Users/xiefei/BrowseCraftCore`

## Scope

- P3-5.9 Candidate/Draft model migration validation.
- Core `SourceRuleCandidateDraftApplier` compile and unit coverage.
- Main App build and `BrowseCraftTests` regression.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

Workdir: `/Users/xiefei/BrowseCraftCore`

Result: passed.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Workdir: `/Users/xiefei/BrowseCraftCore`

Result: passed. `23 tests`, `0 failures`.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -quiet \
  -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/BrowseCraft-P3-5-9-BuildTest-DerivedData
```

Workdir: `/Users/xiefei/BrowseCraft`

Result: passed after fixing the P3-5.9 migration compile gap below.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests \
  -derivedDataPath /private/tmp/BrowseCraft-P3-5-9-BuildTest-DerivedData \
  -resultBundlePath /private/tmp/BrowseCraft-P3-5-9-App.xcresult
```

Workdir: `/Users/xiefei/BrowseCraft`

Result: passed. `111 tests in 22 suites`, `0 failures`.

## Notes

- Initial App build failed because `RuleCandidateField` is now a Core `SourceRuleField` alias, which includes `.chapter`; `SwiftSoupRuleCandidateAnalyzer.isRequiredField(_:)` had a non-exhaustive switch. Fixed by handling `.chapter` as a non-required candidate field.
- Existing warnings remain: redundant `try` warnings in SwiftSoup parser/analyzer and `Any?` to `Any` warning in `WKWebViewHTMLLoader`.
- `.xcresult`: `/private/tmp/BrowseCraft-P3-5-9-App.xcresult`
- DerivedData: `/private/tmp/BrowseCraft-P3-5-9-BuildTest-DerivedData`
- `git diff --check` passed for both `/Users/xiefei/BrowseCraft` and `/Users/xiefei/BrowseCraftCore` after the fix.
