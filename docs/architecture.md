# BrowseCraft architecture

BrowseCraft follows a dependency-inward structure inside the application target:

- `Domain` owns entities and repository contracts.
- `Application` owns use cases, ports, stateful coordinators and runtime orchestration.
- `Infrastructure` implements network, persistence, parsing, StoreKit and platform adapters.
- `Features` owns `@MainActor` presentation state and SwiftUI views.
- `App` is the composition root and the only place allowed to assemble concrete adapters.

The first compile-time slice is `BrowseCraftDomain`, which owns the API-independent catalog contract. Additional stable domain values can move into this framework incrementally without exposing APIKit DTOs to features.

Synchronous persistence use cases are owned by feature-specific actors. View models await immutable snapshots and only mutate published state on `MainActor`. StoreKit transactions are converted to `StoreTransactionSnapshot` before Portal validation and database persistence.

The build runs `scripts/check-architecture-boundaries.sh` to prevent framework imports (UI, persistence, networking, WebKit, CloudKit, Combine) from leaking into `Domain` or `Application`, prevent APIKit from escaping adapters/composition, and prevent new raw `print` logging. Because every layer lives in one module, the script also searches for top-level type names across layers: `Domain` may not reference any other layer, `Application` may not reference `Features`/`Infrastructure`/`App`, `Infrastructure` and `Features` may not reference `App`, and `Shared` may not reference `App` or `Features`. Contracts that both sides need (ports, error enums, shared observable stores) belong to the lower layer.

Database schema evolves only through `Infrastructure/Database/Migrations/AppDatabaseMigrations.swift`. `AppDatabaseSchemaV1` is a frozen literal copy of the `v1.initial-schema` migration that TestFlight devices have already recorded; it is never edited. Every later change is appended as a new `vN.description` migration expressed with `ALTER`/`CREATE`, and `BrowseCraftTests/Infrastructure/Database/AppDatabaseSchemaSnapshotTests.swift` compares the migrated `sqlite_master` against a checked-in snapshot, so a schema change without a migration (or a migration without a snapshot update) fails the tests. Record types keep only their `Columns` and row mapping; they no longer create tables.

`scripts/check-ad-configuration.sh` fails a PROD archive that still carries Google's sample rewarded ad unit and only warns everywhere else.

The explicit video runtime audit (`Application/Runtime/Video/Audit`, the `VideoRuntimeAuditWebUIPresenter` overlay and the WebKit media-event handler in `Features/Library/Video/Player`) compiles only in Debug; Release and TestFlight builds contain none of it. The evidence value types (`VideoRuntimeEvidenceV2`, `VideoRuntimeEvidenceFingerprint`) stay in every build because the playback loader uses them.

`BrowseCraftCore` remains the rule-semantics package. SwiftSoup is confined to its explicitly named DOM/discovery adapters; RSS and rule-loading paths must continue to use their boundary protocols and must not import SwiftSoup.
