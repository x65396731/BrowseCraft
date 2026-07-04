# BrowseCraft P3-8.2 SourceDefinition Mapping Tests Run 1

Date: 2026-07-04

## Scope

P3-8.2 establishes the first neutral source configuration and SourceDefinition mapping boundary.

## Changes Covered

- Added App-domain `SourceConfiguration`.
  - `rule(RuleSourceConfiguration)`
  - `rss(RSSSourceConfiguration)`
  - `plugin(PluginSourceConfiguration)`
- Added `Source.configuration` as a rule-backed compatibility boundary.
- Moved `SourceDefinitionMapper` out of `Application/Runtime/Rule/RuleSourceRuntimeMapping.swift` into `Application/Runtime/SourceDefinitionMapping.swift`.
- Kept `RuleSourceRuntimeMapping.swift` focused on runtime output mapping.
- Added tests for RSS/plugin `SourceConfiguration -> SourceDefinition` mapping without falling back to `SiteRule`.

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
  -derivedDataPath /private/tmp/BrowseCraft-P3-8-2-Test-DerivedData \
  -resultBundlePath /private/tmp/BrowseCraft-P3-8-2-Run1.xcresult
```

```sh
git diff --check
```

## Result

- `SourceRuntimeMappingTests`: 6 tests passed, 0 failures.
- `git diff --check`: passed.
- Result bundle: `/private/tmp/BrowseCraft-P3-8-2-Run1.xcresult`
- DerivedData: `/private/tmp/BrowseCraft-P3-8-2-Test-DerivedData`

## Notes

- No DB migration was introduced in P3-8.2.
- RSS/plugin configs are mapping-ready but do not execute runtime behavior.
- `SourceConfiguration` / `configJSON` remain long-term architecture concepts; legacy `source.rule`, `SourceType`, and `ruleJSON` remain migration compatibility.

