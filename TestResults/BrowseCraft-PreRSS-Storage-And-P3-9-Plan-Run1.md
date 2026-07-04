# BrowseCraft Pre Source-Config Storage And P3-9 Plan Run 1

- Date: 2026-07-04
- Scope: Source storage preparation and P3-9 plan correction after deciding not to make RSS the next mainline.

## Changes

- Added `SourceRecord.sourceConfiguration()` so persisted `kind + configJSON` can decode `.rule`, `.rss`, and `.plugin` source configurations without forcing them into the current UI-facing `Source` model.
- Kept `SourceRecord.domainModel()` rule-only for now; RSS/Plugin records still refuse to create a rule-backed `Source`.
- Added P3-9.0 Source Config Neutralization plan at `TestResults/BrowseCraft-P3-9-0-Source-Config-Neutralization-Plan.md`.

## Command

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -derivedDataPath /private/tmp/BrowseCraft-PreRSS-Fixes-Test-DerivedData -resultBundlePath /private/tmp/BrowseCraft-PreRSS-Fixes-Run1.xcresult`

## Result

- Passed.
- Total: 16
- Passed: 16
- Failed: 0
- Result bundle: `/private/tmp/BrowseCraft-PreRSS-Fixes-Run1.xcresult`

## Key Coverage

- Existing rule-backed source repository behavior still works.
- Legacy `ruleJSON` rows remain readable.
- Runtime-neutral `SourceConfiguration.rule(...)` rows remain readable.
- RSS `SourceConfiguration.rss(...)` rows can be decoded from `configJSON`.
- RSS records are not converted into rule-backed `Source` models.

## Notes

- No Swift files were added or moved, so `./scripts/regenerate-project.sh` was not required.
- No Core source files were changed, so Core `swift test` was not rerun for this small source-config storage fix.
