# Domain Models

Domain models are grouped by the business area that owns the data shape.

- `Source/`: built-in sources, encrypted catalog rules, source import drafts and recommendations, transient discovery items, and rule-generation submissions. `Source`, `ContentItem` and reader chapter models live in the `BrowseCraftDomain` package.
- `History/`: persisted reading/watch history and local user identity used by history records.
- `Library/`: persisted library state.
- `Rule/`: rule analysis stages.
- `Favorites/`: favorite content snapshots.
- `Sync/`: CloudKit account scope, partition and payload models.
- `Settings/`: persisted or selectable app settings models.
- `Book/`: locally imported books (EPUB / audiobook), their reading progress and bookmarks; positions are opaque Readium `Locator` JSON.

Naming rules:

- Prefer one primary model per file, with the file name matching the primary type name.
- Keep tightly-coupled helper enums or small value types in the same file as their primary model.
- Do not leave model files at the `Models/` root; add or reuse a domain folder instead.
