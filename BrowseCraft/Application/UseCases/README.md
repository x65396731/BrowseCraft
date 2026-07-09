# Application UseCases

UseCases are grouped by the app feature boundary that owns the user action.
Do not group this layer by runtime/source type such as `RSS/Video/Comic`; those folders belong under runtime implementations.

- `Source/`: source creation, loading, synchronization, import recommendation, and source runtime refresh.
- `Rule/`: rule editing and package import/export workflows.
- `Library/`: library state, favorites, and library source presentation.
- `Reader/`: reader chapter loading and reader source presentation.
- `History/`: RSS, comic, and video history save/load workflows.

When adding a new use case, place it beside the view model or feature flow that calls it most directly. For example, an RSS history use case belongs in `History/`, while an RSS source import use case belongs in `Source/`.
