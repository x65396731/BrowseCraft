# BrowseCraft P3-8.5c SourceItemReference Mapping Tests Run 1

- Date: 2026-07-04
- Scope: P3-8.5c App rule runtime handoff mapping boundary.
- Result: Passed.

## Changes Verified

- Added `RuleSourceItemReferenceMapper` under `BrowseCraft/Application/Runtime/Rule`.
- The mapper converts App `ContentItem` into Core `SourceItemReference`.
- The mapper preserves:
  - source and item identity
  - title and content type
  - detail URL
  - optional chapter URL
  - cover URL
  - latest text
  - list context
  - request override
  - runtime context
  - handoff intent
- The mapping remains rule-runtime-local and does not replace `ReaderViewModel`.

## Commands

```sh
./scripts/regenerate-project.sh
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/SourceRuntimeMappingTests \
  -derivedDataPath /private/tmp/BrowseCraft-P3-8-5c-Test-DerivedData \
  -resultBundlePath /private/tmp/BrowseCraft-P3-8-5c-Run3.xcresult
```

```sh
git diff --check
git -C /Users/xiefei/Desktop/BrowseCraftCore diff --check
```

## Result Summary

- Test suite: `SourceRuntimeMappingTests`
- Total tests: 8
- Passed: 8
- Failed: 0
- Result bundle: `/private/tmp/BrowseCraft-P3-8-5c-Run3.xcresult`

## Notes

- The first sandboxed `xcodebuild` attempt failed before compilation because it could not access CoreSimulator services and user cache/log locations.
- The authorized rerun completed successfully.
- A second authorized rerun was used after cleaning a redundant test macro warning.
- No Core source changes were made in P3-8.5c beyond using the P3-8.5a/8.5b Core model.
- No UI, ReaderViewModel, parser, network, or cache behavior was changed.
