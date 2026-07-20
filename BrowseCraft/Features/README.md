# Feature Boundaries

`Features` contains exactly the five root pages presented by `RootView`:

- `Sources/`: add, import, edit, debug, and remove sources.
- `Favorites/`: browse saved content snapshots.
- `Library/`: browse and consume source content.
- `History/`: browse persisted reading, watching, and temporary-resource history.
- `Settings/`: account, sync, purchase, and cache preferences.

## Content ownership

Comic, video, and RSS are content capabilities owned by `Library/`, not additional root pages and not independent tabs. Their list, detail, reader, player, and source-access screens stay under:

```text
Library/
├── Comic/
├── Video/
├── RSS/
└── SourceAccess/
```

`Favorites` and `History` may navigate into these Library-owned consumption screens. They should reuse the existing destination views and factories instead of copying content implementations into their own folders.

## Placement rules

- Page-specific presentation state and views stay inside the owning feature.
- Business workflows belong in `Application/UseCases` or `Application/Runtime`.
- Persisted business data belongs in `Domain/Models` and repositories in `Domain/Repositories`.
- Only genuinely cross-feature diagnostics, errors, logging, and reusable UI primitives belong in `Shared/`.
- Do not create a sixth top-level feature for Comic, Video, RSS, Reader, Player, Login, or Tabs.
