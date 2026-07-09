# Domain Models

Domain models are grouped by the business area that owns the data shape.

- `Source/`: source definitions, built-in sources, source import inputs, import recommendations, source types, and list content items emitted by source runtimes.
- `Reader/`: reader navigation and chapter content models.
- `History/`: persisted reading/watch history and local user identity used by history records.
- `Library/`: persisted library state.
- `Rule/`: rule-backed source and candidate analysis data contracts.
- `Settings/`: persisted or selectable app settings models.

Naming rules:

- Prefer one primary model per file, with the file name matching the primary type name.
- Keep tightly-coupled helper enums or small value types in the same file as their primary model.
- Do not leave model files at the `Models/` root; add or reuse a domain folder instead.
