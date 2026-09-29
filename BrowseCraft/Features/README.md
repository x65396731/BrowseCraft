# Feature Boundaries

`Features` contains the five root pages presented by `RootView`, plus two supporting folders:

- `Sources/`: add sources from the rule catalog, submit sites for rule generation (with the entry-page guide), inspect a rule read-only, and remove sources.
- `Favorites/`: browse saved content snapshots.
- `Library/`: browse and consume source content.
- `History/`: browse persisted reading, watching, and temporary-resource history.
- `Settings/`: account, coin balance and ledger, rewarded-ad service, sync, purchase, and cache preferences.
- `Startup/`: the launch animation shown before the root pages (not a root page).
- `Shared/`: state and views shared by several root pages, such as `SourceSelectionStore`.

## Content ownership

Comic, video, and book are content capabilities owned by `Library/`, not additional root pages and not independent tabs. Their list, detail, reader, player, and source-access screens stay under:

```text
Library/
├── Book/
├── Comic/
├── Video/
├── SourceAccess/
├── Components/   # list, search, placeholder and skeleton views shared by the Library tabs
├── Navigation/
└── State/
```

`Favorites` and `History` may navigate into these Library-owned consumption screens. They should reuse the existing destination views and factories instead of copying content implementations into their own folders.

## Placement rules

- Page-specific presentation state and views stay inside the owning feature.
- Business workflows belong in `Application/UseCases` (or the matching `Application/` area such as `Coins/`, `Push/`, `Sync/`); rule execution belongs in the `BrowseCraftRuntime` package.
- Persisted business data belongs in `Domain/Models` and repositories in `Domain/Repositories`.
- Only genuinely cross-feature diagnostics, errors, logging, and reusable UI primitives belong in `Shared/`.
- Do not create a sixth root page for Comic, Video, Book, Reader, Player, Login, or Tabs.
