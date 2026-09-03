# BrowseCraft architecture

BrowseCraft is a rule-driven reader: a *source rule* (JSON) describes how to fetch and parse a
site, and the app executes it. Most architectural decisions here follow from that — the rule
format is the real domain model, and the code is organised around two questions: who may
interpret a rule, and who may touch the network.

## 1. Modules

| Module | Kind | Size | Role |
| --- | --- | --- | --- |
| `BrowseCraft` | app target | ~62k lines | Everything in §2 |
| `BrowseCraftCore` | sibling SwiftPM package | ~29k lines | Rule models, validation, resolved graphs, deterministic parsing |
| `BrowseCraftAPIKit` | sibling SwiftPM package | ~1.3k lines | The BrowseCraft backend contract (endpoints, DTOs, transport) |
| `BrowseCraftDomain` | in-repo framework | 30 lines | Catalog transport contract, isolated from APIKit at compile time |

Dependency direction is `App → Core` and `App → APIKit`; Core and APIKit never reference each
other. `BrowseCraftCore/Documentation/CoreParsingBoundary.md` is the authoritative statement of
what Core may do. The short version: Core is a deterministic function from (bytes + rule +
context) to normalised output, and never performs requests, holds cookies, creates a `WKWebView`,
or knows about the current user.

Core and APIKit are consumed as **path dependencies on sibling checkouts** and carry no version
tags. This is known debt: the app's `main` only builds against the sibling repos' `main`.

## 2. Layers inside the app target

Dependency arrows point inward. Nothing below may reference anything above it.

| Layer | Size | Owns |
| --- | --- | --- |
| `Domain` | 2.4k / 46 files | Entities, 10 repository protocols, pure domain services |
| `Application` | 26.2k / 152 files | 42 use cases, 39 port files, coordinators, and the rule runtime |
| `Infrastructure` | 9.7k / 79 files | GRDB, CloudKit, StoreKit, Alamofire, WebKit, Keychain adapters |
| `Features` | 20.7k / 101 files | `@MainActor` view models and SwiftUI views |
| `Shared` | 1.7k / 18 files | Logging, diagnostics, ads, common image views |
| `App` | 1.8k / 12 files | Composition root, feature factories, startup |

`App/AppContainer.swift` is the only place allowed to assemble concrete adapters, and — besides
`Infrastructure` — the only place allowed to see `BrowseCraftAPIKit`.

### The rule runtime

`Application/Runtime` (15.1k lines: Video 8.1k, Comic 5.5k, RSS 0.6k, Common 0.9k) turns a
resolved rule plus fetched bytes into domain values. It is the largest single thing in the app and
a candidate for extraction into its own package: it already imports nothing but Foundation and
`BrowseCraftCore`, and its collaborators (`PageContentLoader`, `SourceCredentialProviding`, …) are
Foundation-only protocols.

`SourceRuntime` and its capability protocols are declared in **Core**; the app implements them.
Contract in the package, implementation in the app — preserve this shape.

## 3. Enforced invariants

`scripts/check-architecture-boundaries.sh` runs as a pre-build phase and fails the build on:

- **Framework leaks** — `Domain` and `Application` may not import UIKit, SwiftUI, StoreKit, GRDB,
  Alamofire, Nuke, SwiftSoup, WebKit, AVFoundation, CloudKit, Combine, or APIKit.
- **APIKit escape** — `import BrowseCraftAPIKit` is allowed only under `Infrastructure/` and in
  `AppContainer.swift`.
- **Cross-layer type references** — every layer lives in one module, so import checks are blind to
  them. The script also searches each layer's top-level type names in the layers that must not
  depend on it: `Domain` may reference no other layer; `Application` may not reference
  `Features`/`Infrastructure`/`App`; `Infrastructure` and `Features` may not reference `App`;
  `Shared` may not reference `App` or `Features`. When both sides need a contract (a port, an error
  enum, a shared observable store), it belongs to the lower layer.
- **Raw `print`** — use `AppLog` / `AppDebugLog`.
- **SwiftSoup containment in Core** — only the explicitly named DOM/discovery adapters may import
  it; RSS and rule-loading paths go through their boundary protocols.

`scripts/check-ad-configuration.sh` fails a PROD archive that still carries Google's sample
rewarded ad unit, and only warns elsewhere.

## 4. Concurrency

The target builds with `SWIFT_STRICT_CONCURRENCY: complete`.

Every port protocol in `Application/Ports`, every repository in `Domain/Repositories`, and every
Domain value type is `Sendable`; `BrowseCraftCore`'s rule models are `Sendable` too. Use cases and
transfer structs therefore conform without escape hatches. Closures stored by `Sendable` types are
declared `@Sendable`.

`@unchecked Sendable` (20 remaining, all final classes) is reserved for state protected by a lock,
an actor hop, or a serial queue — `AppDatabase`, the identity and account-scope stores, the sync
services, the WebKit and URLSession delegates. A new `@unchecked` needs a comment naming the
synchronisation it relies on.

Synchronous persistence is owned by 22 actors (the `*PersistenceCoordinator` family). View models
await immutable snapshots and mutate published state only on `MainActor`. StoreKit transactions
become `StoreTransactionSnapshot` before Portal validation or database writes.

## 5. Persistence

Schema evolves **only** through `Infrastructure/Database/Migrations/AppDatabaseMigrations.swift`.

`AppDatabaseSchemaV1` is a frozen, literal copy of the `v1.initial-schema` migration that shipped
devices have already recorded — table and column names are string literals, so evolving a `Record`
type cannot silently rewrite history. It is never edited. Every later change is appended as a new
`vN.description` migration expressed with `ALTER`/`CREATE`.

`AppDatabaseSchemaSnapshotTests` runs the migration chain against a fresh database and compares
the resulting `sqlite_master` to a checked-in snapshot, so a schema change without a migration —
or a migration without a snapshot update — fails. `Record` types keep only their `Columns` and row
mapping; they no longer create tables.

## 6. Tests

`BrowseCraftTests` is ~19.7k lines / 82 files, mostly Swift Testing with some XCTest.

ViewModel tests are assembled by `BrowseCraftTests/TestDoubles/ViewModels/ViewModelTestHarness.swift`:
real use cases and persistence coordinators on top of real GRDB repositories against a temporary
SQLite file, with only the network-facing boundaries replaced (`ScriptedSourceRuntime`,
`ScriptedRSSFeedLoader`, stub page/preflight loaders). Extend the harness rather than mocking use
cases per test, so a ViewModel test exercises the orchestration the app actually ships.

Archived preflight fixtures enter the bundle as a folder reference to preserve their `site-*/`
subdirectories.

## 7. Build-time slicing

The explicit video runtime audit — `Application/Runtime/Video/Audit`, the
`VideoRuntimeAuditWebUIPresenter` overlay, and the WebKit media-event handler in
`Features/Library/Video/Player` — compiles **only in Debug**. Release and TestFlight builds contain
none of it, and its plumbing in `AppContainer` and `RootView` is `#if DEBUG` too. The evidence
value types (`VideoRuntimeEvidenceV2`, `VideoRuntimeEvidenceFingerprint`) ship in every build
because the playback loader uses them for route facts.

## 8. Dependencies

Every third-party dependency is a Swift package. There is no CocoaPods step,
`scripts/regenerate-project.sh` is just `xcodegen generate`, and the file to open is
`BrowseCraft.xcodeproj`.

`project.yml` declares the packages;
`BrowseCraft.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is the committed
lock file, and the rest of the generated project stays ignored. Everything is pinned to an exact
version except KSPlayer, which is pinned to a commit because that repository publishes no tags.

Alamofire, GRDB and Nuke link statically into the app binary, so no `@rpath` framework embedding is
involved — the "linked but not embedded" failure mode (ITMS-90863, dyld crash on launch) cannot
occur for them.

## 9. Known debt

- **`App/Compatibility/BrowseCraftCoreCompatibility.swift`** re-exports 156 Core types as
  `typealias`es into the app's global namespace. As a result `Application` (52 files), `Features`
  (9), `Domain` (7) and `Infrastructure` (4) use Core rule models directly, mostly without an
  `import BrowseCraftCore` — so import-based boundary checks are blind to that coupling. Either
  accept that Core's rule models *are* the domain model (delete the shim, make imports explicit) or
  map Core output to app types at the runtime boundary. Deciding this is a prerequisite for
  extracting `Application/Runtime` into its own package.
- **`BrowseCraftDomain` is 30 lines and has not grown since July.** Either migrate stable domain
  values into it on a schedule, or delete it so it stops implying a compile-time boundary that does
  not exist.
- **Core and APIKit are unversioned path dependencies** (see §1).
- **`AppContainer` changes on nearly every feature** — it constructs ~40 objects in one `init` and
  is the most-churned file in the repo. Splitting it into identity / sync / runtime sub-containers
  would decouple those axes.
- **`Shared` mixes concerns** — Firebase, AdMob, logging, image views and review prompts, with four
  `.shared` singletons that have no port and cannot be substituted in tests.
