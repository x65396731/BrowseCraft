# Database Notes

BrowseCraft is still in development. Keep `AppDatabase` focused on the current schema shape instead of production migration compatibility.

Current pending rules:

- `favorites` is now user-scoped: one row per user, keyed by `userID`, with JSON snapshots for RSS / comic / video favorites plus a derived ID list for quick toggle state.
- `favorites` and reading history only reference `users`; they do not reference `sources`, so deleting source-related rows will not cascade into independent user snapshots.
- Decide whether `sources` itself should become user-scoped before adding `userID` to the `Source` domain model and repository API.

Source deletion rule:

- `sources.id` owns source-scoped runtime state and Library selection through `sourceID`.
- Deleting a Source must not delete matching `rss_reading_history`, `comic_chapter_history`, or `video_watch_history` rows.
- Deleting a Source must clear `user_library_state.selectedSourceID`, `listContextJSON`, and `lastRefreshAt` when the selected source matches the deleted source.
- Do not delete `users`.
- Do not delete `favorites` or reading history; source deletion should not touch them because user snapshots are independent of source lifecycle.
