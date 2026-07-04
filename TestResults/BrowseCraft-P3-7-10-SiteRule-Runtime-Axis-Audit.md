# BrowseCraft P3-7.10 SiteRule Runtime Axis Audit

- Date: 2026-07-04
- Scope: P3-7.10 SiteRule JSON role downgrade and runtime-axis documentation.
- Result: Documentation/comment alignment complete. No runtime behavior changes were made.

## Decision

The source architecture axis is:

```text
SourceDefinition + SourceRuntime
```

`SiteRule` is not the App-wide source axis. It is the configuration format for the rule-backed runtime:

```text
SourceRuntime
  RuleSourceRuntime
    config: SiteRule JSON
  RSSSourceRuntime
    config: RSS / Atom definition
  PluginSourceRuntime
    config: plugin manifest / package
```

## Changes

- Updated `BrowseCraft/Application/Runtime/README.md` to document the runtime axis and RSS/plugin slots.
- Updated `RuleSourceRuntimeAdapter` comments to state that it only interprets `SiteRule` JSON for rule-backed sources.
- Updated `Source` comments to describe it as an App persistence entity whose execution semantics are decided by runtime.
- Updated `SourceRuntimeResolver` comments to keep RSS/plugin as independent future runtimes rather than extra `SiteRule` fields.

## Non-Goals

- No RSS runtime implementation.
- No plugin manifest implementation.
- No plugin execution.
- No production behavior change.
- No XcodeGen regeneration because no Swift files were added or moved.
- No simulator test run because this node only changes documentation/comments.

## Drift Check

- `SiteRule` remains editable by the rule editor and usable by `RuleSourceRuntime`.
- Library/Reader did not gain new direct dependencies on `SiteRule` internals.
- App-only dependencies remain outside `BrowseCraftCore`.
- No Bridge layer was restored.
