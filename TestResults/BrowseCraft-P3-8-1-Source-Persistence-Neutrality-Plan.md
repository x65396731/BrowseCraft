# BrowseCraft P3-8.1 Source Persistence Neutrality Plan

Date: 2026-07-04

## Scope

P3-8.1 chooses the neutral source persistence direction before RSS work starts.

This is a design node. No production code was changed. No build or test was run.

## Current Problem

`Source` is still a rule-backed entity:

```swift
struct Source {
    var id: String
    var name: String
    var baseURL: String
    var type: SourceType
    var rule: SiteRule
    ...
}
```

`SourceRecord` persists only `ruleJSON`:

```swift
var ruleJSON: String
```

This means RSS or plugin sources cannot be represented without either inventing placeholder `SiteRule` values or adding non-rule fields to `SiteRule`. Both would violate the runtime-first architecture.

## Options Considered

### Option A: Persist Core `SourceDefinition` directly

Shape:

```text
SourceRecord
  definitionJSON: SourceDefinition
```

Pros:

- Directly matches the Core public contract.
- `kind` already supports rule/rss/plugin.
- Fewer App-only source config types.

Cons:

- `SourceDefinition.rule` currently stores rule metadata, not the full `SiteRule` JSON needed by the rule runtime/editor.
- Rule editor, rule import/export, and built-in rule sync still need `SiteRule`.
- Persisting only `SourceDefinition` would require a second store for rule JSON anyway.

Decision: not enough by itself.

### Option B: App-local `SourceConfiguration` enum

Shape:

```swift
enum SourceConfiguration: Hashable {
    case rule(SiteRule)
    case rss(RSSSourceConfiguration)
    case plugin(PluginSourceConfiguration)
}

struct Source {
    var definition: SourceDefinition
    var configuration: SourceConfiguration
    ...
}
```

Pros:

- Keeps full rule JSON available for rule editor/runtime.
- Can add RSS/plugin config without touching `SiteRule`.
- Preserves App ownership of persistence details.
- Lets Core remain Foundation-only and App-independent.

Cons:

- Adds an App-level config model that must be mapped to Core `SourceDefinition`.
- Requires careful compatibility helpers so rule-heavy code does not all break at once.

Decision: recommended domain direction.

### Option C: DB `kind + configJSON` with phased domain migration

Shape:

```text
sources
  id
  name
  baseURL
  kind          // rule/rss/plugin
  configJSON    // SiteRule, RSS config, or plugin manifest wrapper
  type          // legacy compatibility during migration
  ruleJSON      // legacy compatibility during migration
```

Pros:

- Simple migration path from existing `ruleJSON`.
- Allows RSS/plugin persistence without schema churn for every new runtime.
- Keeps old rule sources readable while domain model is migrated.

Cons:

- Needs versioned config envelope or strict decoding by `kind`.
- Requires migration tests to avoid breaking existing user sources.

Decision: recommended storage direction.

## Recommended Direction

Use a phased combination of Option B and Option C:

`SourceConfiguration` and `configJSON` are long-term architecture concepts. They carry each runtime's own execution configuration. The temporary pieces are the compatibility helpers and legacy columns: `source.rule`, `SourceType`-based routing, and the old `ruleJSON` column during migration.

1. Introduce App-domain `SourceConfiguration`.
   - `rule(SiteRule)` first.
   - `rss(...)` and `plugin(...)` can be added as inert config shapes before real runtimes exist.

2. Keep `SourceDefinition` as the Core-facing identity/runtime metadata contract.
   - It should not be the only persisted payload for rule sources because it does not contain full `SiteRule`.

3. Migrate DB toward `kind + configJSON`.
   - Preserve `ruleJSON` during the migration window.
   - For existing rows, derive `kind = rule` and `configJSON = ruleJSON`.
   - Do not add RSS/plugin fields to `SiteRule`.

4. Add compatibility helpers temporarily:
   - `source.rule` can remain as a compatibility accessor for rule-backed sources during P3-8, but should become unavailable or throwing for non-rule sources.
   - Rule editor/use cases should move toward explicit rule-source APIs.

## Proposed App Model Shape

```swift
struct Source: Identifiable, Hashable {
    var id: String
    var name: String
    var baseURL: String
    var kind: SourceDefinitionKind
    var configuration: SourceConfiguration
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

Compatibility window:

```swift
extension Source {
    var type: SourceType { ... }      // legacy mapping if still needed
    var rule: SiteRule { ... }        // only valid for .rule
}
```

## Proposed Storage Shape

P3-8.2/8.3 should decide exact migration details, but the target should be:

```text
sources
  id
  name
  baseURL
  kind
  configJSON
  enabled
  createdAt
  updatedAt
```

Legacy transition:

```text
sources
  type       // retained temporarily
  ruleJSON   // retained temporarily
```

## Compatibility Requirements

- Built-in rule sources must continue to sync from BrowseCraftRulesKit without changing source IDs.
- User rule import/export must continue to operate on full `SiteRule` JSON.
- Rule editor may continue to edit `SiteRule`, but only for `.rule` sources.
- Library cache and history must keep stable `sourceId`.
- Existing user rows with `ruleJSON` must decode without data loss.
- RSS sources must not require placeholder rule JSON.
- Plugin sources must not execute code in P3-8.

## P3-8.2 Work to Do

P3-8.2 should design and, if appropriate, implement the first boundary:

- Add `SourceConfiguration` model in the App domain or a runtime-local boundary.
- Add mapper between `Source + SourceConfiguration` and Core `SourceDefinition`.
- Decide whether DB migration starts in P3-8.2 or waits until P3-8.3.
- Add tests for rule-source round trip before adding RSS runtime behavior.

## Verification

No tests were run. This node is design-only and does not change production code.
