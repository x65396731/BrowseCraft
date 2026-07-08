# Database Notes

BrowseCraft is still in development. Keep `AppDatabase` focused on the current schema shape instead of production migration compatibility.

Current pending rules:

- `favorites` is now user-scoped: one row per user, keyed by `userID`, with JSON snapshots for RSS / comic / video favorites plus a derived ID list for quick toggle state.
- The table only references `users`; it does not reference `sources`, so deleting source-related tables will not cascade into favorites.
- Decide whether `sources` itself should become user-scoped before adding `userID` to the `Source` domain model and repository API.

Source deletion rule:

- `sources.id` owns source-scoped runtime/history state through `sourceID`.
- Deleting a Source must delete matching `rss_reading_history`, `comic_chapter_history`, and `video_watch_history` rows.
- Deleting a Source must clear `user_library_state.selectedSourceID`, `listContextJSON`, and `lastRefreshAt` when the selected source matches the deleted source.
- Do not delete `users`.
- Do not delete `favorites`; source deletion should not touch it because favorites are independent of source lifecycle.
