# BrowseCraftRuntime

The rule runtime: it turns a resolved rule plus fetched bytes into domain values.

- Depends only on `BrowseCraftDomain` (values, ports, diagnostics) and `BrowseCraftCore`
  (rule models and deterministic parsing). It performs no requests of its own — the app
  supplies `PageContentLoader` / `PageDataLoader` implementations.
- `SourceDetectionLexicon` reads its JSON from this framework's own bundle
  (`Bundle(for:)`), so the lexicon resources must stay inside this directory.
- The Debug-only runtime audit tool lives in the app
  (`BrowseCraft/Application/Diagnostics/VideoRuntimeAudit`); only the evidence value types
  that the playback loader itself uses are here.
