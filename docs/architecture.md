# BrowseCraft architecture

BrowseCraft follows a dependency-inward structure inside the application target:

- `Domain` owns entities and repository contracts.
- `Application` owns use cases, ports, stateful coordinators and runtime orchestration.
- `Infrastructure` implements network, persistence, parsing, StoreKit and platform adapters.
- `Features` owns `@MainActor` presentation state and SwiftUI views.
- `App` is the composition root and the only place allowed to assemble concrete adapters.

The first compile-time slice is `BrowseCraftDomain`, which owns the API-independent catalog contract. Additional stable domain values can move into this framework incrementally without exposing APIKit DTOs to features.

Synchronous persistence use cases are owned by feature-specific actors. View models await immutable snapshots and only mutate published state on `MainActor`. StoreKit transactions are converted to `StoreTransactionSnapshot` before Portal validation and database persistence.

The build runs `scripts/check-architecture-boundaries.sh` to prevent framework imports from leaking into `Domain` or `Application`, prevent APIKit from escaping adapters/composition, and prevent new raw `print` logging.

`BrowseCraftCore` remains the rule-semantics package. SwiftSoup is confined to its explicitly named DOM/discovery adapters; RSS and rule-loading paths must continue to use their boundary protocols and must not import SwiftSoup.
