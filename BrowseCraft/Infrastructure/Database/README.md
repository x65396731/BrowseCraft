# Database Notes

BrowseCraft is still in development. Keep `AppDatabase` focused on the current schema shape instead of production migration compatibility.

Current pending rules:

- Redesign `favorites` before expanding it. The likely shape is `userID + sourceID + itemID + contentKind + createdAt`, but favorite behavior is not being redesigned yet.
- Decide whether `sources` itself should become user-scoped before adding `userID` to the `Source` domain model and repository API.

Source deletion rule:

- `sources.id` owns source-scoped runtime/history state through `sourceID`.
- Deleting a Source must delete matching `rss_reading_history`, `comic_chapter_history`, and `video_watch_history` rows.
- Deleting a Source must clear `user_library_state.selectedSourceID`, `listContextJSON`, and `lastRefreshAt` when the selected source matches the deleted source.
- Do not delete `users`.
- Do not delete `favorites` until the favorite table is redesigned.
