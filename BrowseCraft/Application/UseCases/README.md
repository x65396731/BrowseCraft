# Application UseCases

UseCases are grouped by the app feature boundary that owns the user action.
Prefer that grouping over runtime/source type; `Book/` and `Comic/` exist because those user actions (local books, comic detail) have no other owning feature.

- `Source/`: adding catalog sources, loading, synchronization, import recommendation, discovery, generation-input assessment, source runtime refresh, and the read-only rule debug formatter.
- `Generation/`: rule-generation submission, outcomes, catalog grouping, and personal-rule retention.
- `Ads/`: rewarded-ad points.
- `Favorites/`: favorites persistence.
- `Comic/`: comic detail loading.
- `Library/`: library state, favorite toggling, and library source presentation.
- `Reader/`: reader chapter loading and reader source presentation.
- `History/`: comic, video, and book history save/load workflows.
- `Book/`: local book import, opening, reading progress, and bookmarks (ports live in `Application/Ports/Book/`).

When adding a new use case, place it beside the view model or feature flow that calls it most directly. For example, a comic history use case belongs in `History/`, while a comic source import use case belongs in `Source/`.
