# BrowseCraftCore P3-7.12 Physical Layer Restructure Run 1

- Date: 2026-07-04
- Scope: P3-7.12 Core physical layer restructure.
- Result: Passed.

## Changes

Moved `BrowseCraftCore` source files from the old broad `Models/` bucket into more specific physical layers:

```text
Sources/BrowseCraftCore/
  Runtime/
    SourceRuntime.swift
    SourceRuntimeError.swift
    SourceRuntimeModels.swift
  Diagnostics/
    SourceDebugModels.swift
    SourceRuntimeDiagnostics.swift
  Source/
    ContentType.swift
    SourceDefinition.swift
  Rule/
    SiteRule.swift
    ResolvedSiteRule.swift
    RuleValidator.swift
    RulePackageCodec.swift
    SourceRulePrimitives.swift
    Candidate/
      SourceRuleCandidateModels.swift
      SourceRuleCandidateDraftApplier.swift
  Serialization/
    StableJSONCoding.swift
```

No public API behavior was changed. The move is physical organization only.

## Verification

- Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test`
- Working directory:
  `/Users/xiefei/Desktop/BrowseCraftCore`
- Result: Passed.
- Total: 34 XCTest tests passed, 0 failures.

## Notes

- No App code was changed for this node.
- No XcodeGen regeneration was needed.
- `ContentType.swift` moved to `Source/` because it describes the normalized content category produced by source runtimes.
