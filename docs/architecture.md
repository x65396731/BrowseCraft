# BrowseCraft architecture

BrowseCraft is a rule-driven reader: a *source rule* (JSON) describes how to fetch and parse a
site, and the app executes it. Most architectural decisions here follow from that — the rule
format is the real domain model, and the code is organised around two questions: who may
interpret a rule, and who may touch the network.

## 1. Modules

| Module | Kind | Size | Role |
| --- | --- | --- | --- |
| `BrowseCraft` | app target | ~65k lines | Everything in §2 |
| `BrowseCraftCore` | sibling SwiftPM package | ~30k lines | Rule models, validation, resolved graphs, deterministic parsing |
| `BrowseCraftAPIKit` | sibling SwiftPM package | ~1.9k lines | The BrowseCraft backend contract (endpoints, DTOs, transport) |
| `BrowseCraftDomain` | sibling SwiftPM package | ~2.3k lines | Domain kernel: values, ports, policies and diagnostics shared by the app and the rule runtime |
| `BrowseCraftRuntime` | sibling SwiftPM package | ~14k lines | The whole rule runtime: Book, Comic, Video and the shared dispatch |

**Core's rule models are this app's domain model.** `SiteRule`, `VideoSiteRule`, `ListContext`,
`RequestConfig` and the resolved graphs are used directly by `Domain`, `Application` and
`Features`; every call site says `import BrowseCraftCore`, so the dependency is visible to the
compiler and to the boundary checks. There is no re-export shim and no parallel app-side copy of
the rule model — a parallel copy would also have to be persisted, since a rule's `Codable` form is
what lands in `sources.configJSON` and syncs through CloudKit.

Dependency direction is `App → Core`, `App → APIKit`, `App → Domain` and `App → Runtime`;
`Runtime → Core` / `Domain`, and `Domain → BrowseCraftRuleModels` (a target of the Core package).
Core and APIKit never reference each other. `BrowseCraftCore/docs/design/CoreParsingBoundary.md` is the authoritative statement of
what Core may do. The short version: Core is a deterministic function from (bytes + rule +
context) to normalised output, and never performs requests, holds cookies, creates a `WKWebView`,
or knows about the current user.

All four packages are consumed as **path dependencies on sibling checkouts** and carry no version
tags. This is known debt: the app's `main` only builds against the sibling repos' `main`, and a
fresh machine has to clone all five repositories side by side under one parent directory, plus the
SwiftSoup fork that overrides the dependency graph (§8):

```
<parent>/
  BrowseCraft/            # the app
  BrowseCraftCore/
  BrowseCraftDomain/
  BrowseCraftRuntime/
  BrowseCraftAPIKit/
  SwiftSoup/              # local override package (BCA-BUILD-002)
```

## 2. Layers inside the app target

Dependency arrows point inward. Nothing below may reference anything above it.

| Layer | Size | Owns |
| --- | --- | --- |
| `Domain` | 1.7k / 44 files | Entities, 13 repository protocols, pure domain services |
| `Application` | ~13.9k / 106 files | 50 use cases, the remaining ports, coordinators, the coin wallet and push handling |
| `Infrastructure` | 13.1k / 99 files | GRDB, CloudKit, Alamofire, WebKit, Keychain adapters (StoreKit stays in `Features`, see §9) |
| `Features` | 29.9k / 109 files | `@MainActor` view models and SwiftUI views |
| `Shared` | 2.7k / 26 files | Logging, diagnostics, ads, common image views |
| `App` | 3.0k / 21 files | Composition root, feature factories, startup, the Debug-only demo mode (`App/Demo`) |

`App/Composition` is the composition root: the only place allowed to assemble concrete adapters,
and — besides `Infrastructure` — the only place allowed to see `BrowseCraftAPIKit`. It is split by
what owns the objects rather than by layer:

- `AccountComposition` — business identity, Portal session and entitlements, CloudKit sync
  partitioning, and the two repositories whose writes notify sync. Identity and sync are grouped
  because they genuinely depend on each other (the sync coordinator needs the active user; the
  identity-adoption coordinator needs the sync coordinator), so splitting them would only produce
  back-references.
- `SourceRuntimeComposition` — the network carriers and the three runtime factories, i.e. wiring
  the app's concrete adapters onto the kernel ports the runtime consumes.
- `FeatureComposition` — the per-screen factories, the only place that knows which screen needs what.
- `AppContainer` (one level up, in `App/`) holds those three and keeps what is genuinely app-lifecycle: the StoreKit
  transaction listener, image-cache configuration, the push and remote-notification entry points
  (device token, rule-generation push, CloudKit notification), foreground refresh of the coin
  balance, and the Debug-only audit entry point.

### The domain kernel

`BrowseCraftDomain` holds what both the app and the rule runtime need:

- **Domain values** — `Source` and its configuration, `ContentItem`, `ReaderChapter` and the
  protected-resource references, `ChapterLink`, `URLResolvingService`, the video-generation
  preflight values, and `AppUserIdentity.localDefaultID`.
- **Ports** (`BrowseCraftDomain/Ports`) — the contracts the runtime consumes and the app
  implements: content and data loading, credentials, cryptography, request headers.
- **Diagnostics** (`BrowseCraftDomain/Diagnostics`) — `RuleExecutionStage`, `RuleExecutionError`,
  `RuleExecutionLogger`, and `RuleRuntimeDebugLog`. The app installs the log sink at startup and
  maps each record back to its `AppLog` category, so packaged code never depends on the app's
  OSLog categories. `RuleExecutionErrorClassifier` (user-facing messages) stays in the app.
- **Mapping** — `SourceDefinitionMapper`, which both the runtime and the app's use cases need.

It depends on `BrowseCraftRuleModels` (the rule-model target of the `BrowseCraftCore` package; a `Source`'s configuration embeds a rule) and on nothing else, so it never links SwiftSoup.

The rule for what belongs here is narrow: **a type moves into the kernel when both the app and
the runtime need it**, not merely because it feels domain-ish. Entities that only the app uses —
`AppUser`, favourites, history, the repository protocols — stay in `BrowseCraft/Domain`.

### The rule runtime

The rule runtime turns a resolved rule plus fetched bytes into domain values, and now lives
entirely in `BrowseCraftRuntime`. It imports nothing but Foundation, CryptoKit (only the audit
evidence fingerprint, for `SHA256`), `BrowseCraftCore` and `BrowseCraftDomain`; the app supplies every loader, credential store and header provider through
kernel ports. `SourceDetectionLexicon` reads its JSON from the package's resource bundle (`Bundle.module`,
declared as `.process` in `Package.swift`). `Bundle(for:)` would resolve to the app bundle once the
package links statically, find nothing, and silently fall back.

- `BCA-ARCH-006` Resource lookup inside a SwiftPM package must always go through `Bundle.module`.

The Debug-only runtime audit is a developer tool, not runtime semantics, so it stays in the app at
`Application/Diagnostics/VideoRuntimeAudit` — it drives the runtime and depends on app use cases.
Only the evidence value types the playback loader itself uses live in the framework.

Extraction turns up two mechanical consequences worth knowing:

- `BCA-ARCH-007` A `public` struct in a package no longer gets `Sendable` inferred, so it must
  declare the conformance explicitly; and members of a `private` extension must not carry `public`.
Apart from that one CryptoKit import it depends on Foundation, `BrowseCraftCore` and `BrowseCraftDomain` only, and its
collaborators (`PageContentLoader`, `SourceCredentialProviding`, …) are Foundation-only protocols.
Slot-limit decisions are not runtime semantics: `SourceRuntimeFactory` takes an injected
`validateSourceAccess` closure, and its own fallback raises a plain `SourceRuntimeError`.

`SourceRuntime` and its capability protocols are declared in **Core**; `BrowseCraftRuntime`
implements them (`ComicSourceRuntime`, `VideoSourceRuntime`, `BookSourceRuntime`). The app only adds
the Debug-only `DemoSourceRuntime`. Contract in Core, implementation in the runtime package —
preserve this shape.

## 3. Enforced invariants

Each clause below is its single definition point in this repository (`BCA-DOC-002`); `AGENTS.md`
and the design documents reference them by ID and do not restate the text.

`scripts/check-architecture-boundaries.sh` runs as a pre-build phase and fails the build on:

- `BCA-ARCH-001` **SwiftSoup containment.** `Domain`, `Application` and `Features` may not
  `import SwiftSoup`, and neither may the rule-loading chain: the source runtimes
  (`ComicSourceRuntime`, `VideoSourceRuntime`, `BookSourceRuntime` in `BrowseCraftRuntime`) do
  their loading, assembly, request, rule materialisation, error classification and entry dispatch
  through boundary protocols only — `VideoRuleSourceParsingService`, `HTMLDocumentParsing`,
  `ResolvedComicRuleParsing` and their siblings. CSS selector and DOM parsing stay inside the
  explicitly named adapters that may import SwiftSoup, which in Core are exactly three:
  `SwiftSoupHTMLDocumentParser`, `DefaultSourceListStructureObserver` and
  `DefaultSourceDiscoveryAnalyzer`. Readium's own internal use of SwiftSoup is not a breach of
  this clause.
- `BCA-ARCH-002` **No framework leaks.** `Domain` and `Application` may not import UIKit, SwiftUI,
  StoreKit, GRDB, Alamofire, Nuke, SwiftSoup, WebKit, AVFoundation, CloudKit, Combine, MediaPlayer,
  the Readium modules (`ReadiumShared` / `ReadiumStreamer` / `ReadiumNavigator` /
  `ReadiumAdapterGCDWebServer`), or APIKit. Readium `Locator` values cross those layers only as
  opaque JSON strings.
- `BCA-ARCH-003` **No APIKit escape.** `import BrowseCraftAPIKit` is allowed only under
  `Infrastructure/` and in the composition root `App/Composition/`.
- `BCA-ARCH-004` **No cross-layer type references.** Every layer lives in one module, so import
  checks are blind to them. The script also searches each layer's top-level type names in the
  layers that must not depend on it: `Domain` may reference no other layer; `Application` may not
  reference `Features`/`Infrastructure`/`App`; `Infrastructure` and `Features` may not reference
  `App`; `Features` may not construct `Infrastructure` types (inject them through `Application`
  ports); `Shared` may not reference `App`, `Features`, `Application` or `Infrastructure`. When both
  sides need a contract (a port, an error enum, a shared observable store), it belongs to the lower layer.
- `BCA-ARCH-005` **No raw `print`, no `try!`.** Use `AppLog` / `AppDebugLog`; handle or propagate
  errors. Both checks cover the app target and the `Sources/` of all four packages.
- The same script also pins the language mode: `project.yml` must say `SWIFT_VERSION: "6.0"` and
  every package manifest must be `swift-tools-version: 6.0` with an explicit `.swiftLanguageMode(.v6)`
  (§4).
- `BCA-UI-003` The app exposes no entry point that creates or edits a source rule. Rules arrive
  only through the server catalog (`PortalCatalogAPI`, stored encrypted in the snapshot);
  `SourceDebugView` shows them read-only. Rule generation, normalisation and catalog publication
  contracts therefore live entirely in the fwq repository and are neither defined nor referenced here.

Further build rules (the SwiftSoup, ad-configuration and bundled-asset scripts run as pre-build
phases next to the boundary script; `scripts/check-localization.py` runs after compilation; see
`scripts/README.md`):

- `BCA-BUILD-001` The project is managed with XcodeGen. When `.xcodeproj` errors come from added,
  moved or removed source files, run `scripts/regenerate-project.sh` before continuing with
  whatever test or build was asked for.
- `BCA-BUILD-002` SwiftSoup is pinned to the in-house fork `x65396731/SwiftSoup` (branch
  `browsecraft/text-whitespace-fix`: the in-house inline-whitespace fix plus one change so that a repeated
  attribute on the same tag keeps its first value, fwq `BC-ACQ-074`, merged with upstream master): BrowseCraftCore pins it by commit and the project overrides
  the whole dependency graph with the local `../SwiftSoup` package to resolve the identity clash
  with Readium. Both must sit on the same commit.
  `scripts/check-swiftsoup-override.sh` runs next to the boundary script and fails the build when
  the local override is missing, dirty, or not at the commit BrowseCraftCore pins (§8). When Core
  moves its pin, fetch in `../SwiftSoup` and check out the same commit. Before upgrading or moving
  back to the official package, run the inline-whitespace gate case in `RuleExtractionEngineTests`
  and the fork's `BrowserParityTest`.
- `BCA-BUILD-003` `scripts/check-ad-configuration.sh` fails a PROD archive that still carries
  Google's sample rewarded ad unit, and only warns elsewhere. The **TEST BrowseCraft** scheme
  archives config `TestFlight` (environment TEST); the plain **BrowseCraft** and **PROD BrowseCraft**
  schemes archive `Release` as PROD. Debug, TestFlight and Release all carry the real rewarded ad
  unit in `BROWSECRAFT_REWARDED_AD_UNIT_ID`, so the check currently passes for every configuration.
- `BCA-BUILD-004` Project settings must live in tracked source files — `project.yml` for build
  settings, signing (including `DEVELOPMENT_TEAM`), entitlements and capabilities, and the hand-written
  `BrowseCraft/Info.plist` it points to (`GENERATE_INFOPLIST_FILE: NO`) for plist keys such as
  `UIBackgroundModes`. `project.pbxproj` is generated and git-ignored, so anything set through Xcode's
  editors is wiped by the next `scripts/regenerate-project.sh`.

The app target is iPhone-only (`TARGETED_DEVICE_FAMILY: "1"`) until the iPad layout is done.

## 4. Concurrency

The target builds in the Swift 6 language mode (`SWIFT_VERSION: "6.0"`) with
`SWIFT_STRICT_CONCURRENCY: complete`; the four packages declare `.swiftLanguageMode(.v6)`.

Every port protocol in `Application/Ports`, every repository in `Domain/Repositories`, and every
Domain value type is `Sendable`; `BrowseCraftCore`'s rule models are `Sendable` too. Use cases and
transfer structs therefore conform without escape hatches. Closures stored by `Sendable` types are
declared `@Sendable`.

`@unchecked Sendable` (30 remaining) is reserved for state protected by a lock,
an actor hop, or a serial queue — `AppDatabase`, the identity and account-scope stores, the sync
services, the WebKit and URLSession delegates. A new `@unchecked` needs a comment naming the
synchronisation it relies on.

Synchronous persistence is owned by the seven `*PersistenceCoordinator` actors. View models
await immutable snapshots and mutate observable state only on `MainActor`.

View models are `@Observable` (iOS 17 Observation), observed by views with `@State` for ownership
and `@Bindable` where a binding projection is needed. Five types deliberately stay
`ObservableObject`: `SourceSelectionStore`, because `LibraryViewModel` and `SourcesViewModel`
subscribe to its `$` publishers to coordinate across tabs, and the four `NSObject`-based WebView /
ad-presenter coordinators that also serve as UIKit delegates. The macro turns stored properties into computed ones, which a
nonisolated `deinit` may not read:

- `BCA-ARCH-008` Task handles touched in `deinit` must be marked `@ObservationIgnored`.

StoreKit transactions become `StoreTransactionSnapshot` before Portal validation or database writes.

## 5. Persistence

Schema evolves **only** through `Infrastructure/Database/Migrations/AppDatabaseMigrations.swift`.

`AppDatabaseSchemaV1` is a frozen, literal copy of the `v1.initial-schema` migration that shipped
devices have already recorded — table and column names are string literals, so evolving a `Record`
type cannot silently rewrite history. It is never edited, and every later change is appended as a
new `vN.description` migration expressed with `ALTER`/`CREATE` — the clause is `BCA-DB-002`,
defined in `BrowseCraft/Infrastructure/Database/README.md`.

`AppDatabaseSchemaSnapshotTests` runs the migration chain against a fresh database and compares
the resulting `sqlite_master` to a checked-in snapshot, so a schema change without a migration —
or a migration without a snapshot update — fails. `Record` types keep only their `Columns` and row
mapping; they no longer create tables.

## 6. Tests

`BrowseCraftTests` is ~26.3k lines / 124 files, mostly Swift Testing with some XCTest.

ViewModel tests are assembled by `BrowseCraftTests/TestDoubles/ViewModels/ViewModelTestHarness.swift`:
real use cases and persistence coordinators on top of real GRDB repositories against a temporary
SQLite file, with only the network-facing boundaries replaced (`ScriptedSourceRuntime`,
`StubPageContentLoader`, `StubPreflightPageLoader`, `StubPageDataLoader`). Extend the harness rather than mocking use
cases per test, so a ViewModel test exercises the orchestration the app actually ships.

Archived preflight fixtures enter the bundle as a folder reference to preserve their `site-*/`
subdirectories.

## 7. Build-time slicing

The explicit video runtime audit — `Application/Diagnostics/VideoRuntimeAudit`, the
`VideoRuntimeAuditWebUIPresenter` overlay, and the WebKit media-event handler in
`Features/Library/Video/Player` — compiles **only in Debug**. Release and TestFlight builds contain
none of it, and its plumbing in `AppContainer` and `RootView` is `#if DEBUG` too. The evidence
value types (`VideoRuntimeEvidenceV2`, `VideoRuntimeEvidenceFingerprint`) ship in every build
because the playback loader uses them for route facts.

The demo mode (`App/Demo`, launched with `-BrowseCraftDemoMode`) is `#if DEBUG` as well: it runs on a
separate demo database and a `DemoSourceRuntime` with made-up content. The AdMob test-device tools
(`Shared/Ads/AdTestDeviceTools.swift`) compile only under `BROWSECRAFT_AD_TEST_TOOLS`, which Debug and
TestFlight set and Release does not.

## 8. Dependencies

Every third-party dependency is a Swift package. There is no CocoaPods step,
`scripts/regenerate-project.sh` is just `xcodegen generate`, and the file to open is
`BrowseCraft.xcodeproj`.

`project.yml` declares the packages;
`BrowseCraft.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is the committed
lock file, and the rest of the generated project stays ignored. Everything is pinned to an exact
version except KSPlayer, which is pinned to a commit because that repository publishes no tags;
GoogleMobileAds and Firebase, which `project.yml` declares as `from: 12.0.0` and only
`Package.resolved` locks; and SwiftSoup, which is pinned to a commit of our own fork (below).

**Readium** (`readium/swift-toolkit`, exact 3.x tag) serves the book kind only: EPUB/PDF/audiobook
navigators and the `Locator` model for bookmarks and resume positions. The comic reader stays the
in-house SwiftUI reader; Readium's CBZ navigator is not wired. The app links `ReadiumShared`,
`ReadiumStreamer` and `ReadiumNavigator`.

**SwiftSoup fork and local override.** Readium requires SwiftSoup ≥ 2.13.5. Released 2.13.5 and
later drop the whitespace between adjacent inline elements after non-ASCII text, which glues
together tag/cast lists on CJK sites; upstream master has fixed this but not released it. Upstream
also keeps the *last* value of a repeated attribute on one tag, while the HTML5 tokenizer rules,
WebKit and the rule engine's `html5lib` keep the *first* (fwq `BC-ACQ-074`). BrowseCraftCore
therefore pins `x65396731/SwiftSoup` by commit on branch `browsecraft/text-whitespace-fix`: the in-house
whitespace fix and that one tokenizer change, merged with upstream master. These changes stay in the fork and are not
submitted upstream. Because Readium refers to
`scinfu/SwiftSoup` by URL and SwiftPM refuses two URLs for the same package identity, `project.yml`
also adds `../SwiftSoup` as a local package: Xcode lets a local package override every remote
reference to the same identity, so Readium is served by the fork too. The local checkout must sit
at the commit Core pins; `scripts/check-swiftsoup-override.sh` verifies that (and a clean working
tree) as a pre-build phase. When upstream releases both the whitespace fix and the repeated-attribute
change, switch Core back to the official URL and remove the local package and the script; the
inline-whitespace gate test in `RuleExtractionEngineTests` and the fork's `BrowserParityTest` guard
the behaviour either way.

Alamofire, GRDB and Nuke link statically into the app binary, so no `@rpath` framework embedding is
involved — the "linked but not embedded" failure mode (ITMS-90863, dyld crash on launch) cannot
occur for them.

## 9. Known debt

- **`Features` imports `BrowseCraftCore` in 27 files.** Now that the dependency is explicit (§1)
  it is at least visible, but the UI layer reading `SiteRule` directly means a rule-format change
  can ripple into views. Narrowing this to presentation values resolved in `Application` is worth
  doing incrementally; it is not a blocker for anything.
- **Core and APIKit are unversioned path dependencies** (see §1).
- **`Shared` mixes concerns** — Firebase, AdMob, logging, image views and review prompts, with four
  `.shared` singletons that have no port and cannot be substituted in tests.
- **StoreKit is adapted in `Features`, not `Infrastructure`.** `InAppPurchaseStore`
  (`Features/Settings/Premium`) holds `StoreKit.Product` / `Transaction` directly, the
  `StoreTransactionSnapshot` mapping lives in `SettingsViewModel`, and the transaction listener in
  `AppContainer`. Ruled on 2026-10-10 to leave as is: StoreKit 2 types are `Sendable` values rather
  than SDK handles needing a wrapper, the store is UI state with no second implementation to swap,
  and the testability the layering is meant to buy is already provided by `StoreTransactionSnapshot`
  before Portal validation.
