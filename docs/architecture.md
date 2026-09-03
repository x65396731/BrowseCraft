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
| `BrowseCraftDomain` | in-repo framework | ~1.6k lines | Domain kernel: values, ports and diagnostics shared by the app and the rule runtime |
| `BrowseCraftRuntime` | in-repo framework | ~0.6k lines | The rule runtime; RSS today, Comic and Video to follow |

**Core's rule models are this app's domain model.** `SiteRule`, `VideoSiteRule`, `ListContext`,
`RequestConfig` and the resolved graphs are used directly by `Domain`, `Application` and
`Features`; every call site says `import BrowseCraftCore`, so the dependency is visible to the
compiler and to the boundary checks. There is no re-export shim and no parallel app-side copy of
the rule model — a parallel copy would also have to be persisted, since a rule's `Codable` form is
what lands in `sources.configJSON` and syncs through CloudKit.

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
| `Application` | ~25.9k / 136 files | 42 use cases, the remaining ports, coordinators, and the rule runtime |
| `Infrastructure` | 9.7k / 79 files | GRDB, CloudKit, StoreKit, Alamofire, WebKit, Keychain adapters |
| `Features` | 20.7k / 101 files | `@MainActor` view models and SwiftUI views |
| `Shared` | 1.7k / 18 files | Logging, diagnostics, ads, common image views |
| `App` | 1.8k / 12 files | Composition root, feature factories, startup |

`App/AppContainer.swift` is the only place allowed to assemble concrete adapters, and — besides
`Infrastructure` — the only place allowed to see `BrowseCraftAPIKit`.

### The domain kernel

`BrowseCraftDomain` holds what both the app and the rule runtime need:

- **Domain values** — `Source` and its configuration, `ContentItem`, `ReaderChapter` and the
  protected-resource references, `ChapterLink`, `URLResolvingService`, the video-generation
  preflight values, and `AppUserIdentity.localDefaultID`.
- **Ports** (`BrowseCraftDomain/Ports`) — the contracts the runtime consumes and the app
  implements: content and data loading, credentials, cryptography, request headers.
- **Diagnostics** (`BrowseCraftDomain/Diagnostics`) — `RuleExecutionStage`, `RuleExecutionError`,
  and `RuleRuntimeDebugLog`, whose sink the app installs at startup so packaged code never
  depends on the app's OSLog categories. `RuleExecutionErrorClassifier` (user-facing messages and
  logging) stays in the app.
- **Mapping** — `SourceDefinitionMapper`, which both the runtime and the app's use cases need.

It depends on `BrowseCraftCore` (a `Source`'s configuration embeds a rule) and on nothing else.

The rule for what belongs here is narrow: **a type moves into the kernel when both the app and
the runtime need it**, not merely because it feels domain-ish. Entities that only the app uses —
`AppUser`, favourites, history, the repository protocols — stay in `BrowseCraft/Domain`.

### The rule runtime

The rule runtime turns a resolved rule plus fetched bytes into domain values. It is being moved
into `BrowseCraftRuntime` in stages: the domain kernel was the first, RSS the second. What remains
in `Application/Runtime` is Comic (5.5k), Video (8.1k, including the Debug-only audit) and Common
(0.8k); `SourceRuntimeFactory` moves last because it wires all three.
It already imports nothing but Foundation, `BrowseCraftCore` and `BrowseCraftDomain`, and its
collaborators (`PageContentLoader`, `SourceCredentialProviding`, …) are Foundation-only protocols.
Slot-limit decisions are not runtime semantics: `SourceRuntimeFactory` takes an injected
`validateSourceAccess` closure, and its own fallback raises a plain `SourceRuntimeError`.

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

- **`Features` touches Core rule models in 24 files.** Now that the dependency is explicit (§1)
  it is at least visible, but the UI layer reading `SiteRule` directly means a rule-format change
  can ripple into views. Narrowing this to presentation values resolved in `Application` is worth
  doing incrementally; it is not a blocker for anything.
- **Comic and Video are still inside the app target.** Remaining stages: replace the ~43 static
  `AppDebugLog`/`RuleExecutionLogger` calls in those runtimes with the injected sink, then move
  Comic, then Video and `SourceRuntimeFactory`. Types referenced from outside the runtime need
  `public` and, for structs, an explicit `public init`.
- **Core and APIKit are unversioned path dependencies** (see §1).
- **`AppContainer` changes on nearly every feature** — it constructs ~40 objects in one `init` and
  is the most-churned file in the repo. Splitting it into identity / sync / runtime sub-containers
  would decouple those axes.
- **`Shared` mixes concerns** — Firebase, AdMob, logging, image views and review prompts, with four
  `.shared` singletons that have no port and cannot be substituted in tests.
