# Test-service quick-win refactors — Implementation Plan

## Overview

Implement Candidates B and C from `context/changes/refactor-opportunities/research.md`: remove a confirmed-dead 5-method cluster from `TestService.swift`, deduplicate the `passedValue` argument-parsing helper (4 identical copies across 2 Swift modules) into one shared `TuistSupport` utility, and close the one place `TestService.swift` constructs a generated OpenAPI type (`Components.Schemas.ShardPlan`) directly instead of going through its servicing protocol. Candidate A (the `TestService`/`XcodeBuildTestCommandService` shared-orchestrator extraction) is explicitly out of scope for this plan — see "What We're NOT Doing."

## Current State Analysis

All three changes target code confirmed dead-simple and zero-risk by two independent research passes (initial synthesis + an ast-grep-backed verification pass, see `research.md`'s "Weryfikacja twierdzeń" section):

- **Dead cluster**: `xcodebuildDestination`, `simulatorPlatform`, `xcodebuildPlatform`, `hasConcreteDevice`, `xcodebuildDestinationParameter` (`TestService.swift:2239-2309`) have zero callers anywhere in `cli/Sources`/`cli/Tests` outside each other — verified by `ast-grep`/`grep` in this session. They were added together with a caller chain (`e9ada0dbbe`, 2026-06-15) that a later commit (`a99aab2244`, 2026-07-01) removed without removing the leaves.
- **`passedValue` duplication**: identical 5-line bodies in `TestService.swift:2170-2175` (unused — zero internal callers), `XcodeBuildTestCommandService.swift:351-358`, `XcodeBuildBuildCommandService.swift:289-297` (all `TuistKit`), and `XcodeBuildArgumentParser.swift:48-56` (`TuistAutomation`). All three still-used copies are called only as unqualified `passedValue(...)` from within their own file, and all three files already `import TuistSupport` — the common dependency both modules share (`Package.swift:1340` for `TuistKit`, `:1480` for `TuistAutomation`).
- **OpenAPI seam**: `TestService.swift:1476-1488` (`outputEmptyShardMatrixIfNeeded`) is the file's only direct construction of a generated `Components.Schemas.*`/`Operations.*` type (verified: exactly one `ast-grep` match, `:1479`). `ShardMatrixOutputServicing` (`ShardMatrixOutputService.swift:11-13`) is `@Mockable` and has exactly one requirement, `output(_ shardPlan: Components.Schemas.ShardPlan)`; four existing tests in `TestServiceTests.swift` (declarations at `:1259,1263,1267,1275`) assert this method is called with `shard_count == 0 && shards.isEmpty` via the shared `assertSkippedTestReport` helper (`:4583`, assertion at `:4649-4651`).

## Desired End State

- `TestService.swift` no longer declares the five dead helper methods, its own unused `passedValue`, or any direct reference to `Components.Schemas.*`/`Operations.*`.
- `passedValue(for:arguments:)` exists exactly once, as a `public` function in `TuistSupport`; the three call sites that used it (in `XcodeBuildTestCommandService`, `XcodeBuildBuildCommandService`, `XcodeBuildArgumentParser`) are unchanged at the call-site syntax level and behave identically.
- `ShardMatrixOutputServicing` gains a default `outputEmpty()` operation; `TestService.outputEmptyShardMatrixIfNeeded` calls it instead of hand-building the placeholder.
- All pre-existing tests pass unchanged (the four `TestServiceTests` empty-shard-matrix assertions in particular, since they exercise behavior, not construction site). One new test is added directly covering `outputEmpty()` against the concrete `ShardMatrixOutputService`.
- Verified via: `xcodebuild build`/`test` (targeted suites per phase below), `mise run lint`, and a local CLI smoke test of `tuist test` / `tuist xcodebuild test` / `tuist xcodebuild build`.

### Key Discoveries:

- `TestService.swift`'s own `passedValue` copy (`:2170-2175`) is already unused even within that file — it is deleted outright in Phase 1, not migrated to `TuistSupport` in Phase 2.
- All three still-live `passedValue` call sites resolve as unqualified function calls (implicit module-scope lookup once the local `private func` shadow is removed) — because all three files already `import TuistSupport`, no call site needs editing, only the local declarations are deleted.
- `ShardMatrixOutputServicing`'s `@Mockable` macro only generates mock overrides for protocol *requirements*. A protocol *extension* with a concrete body (like the new `outputEmpty()`) is inherited unmodified by `MockShardMatrixOutputServicing`, so calling `outputEmpty()` on a mock in a test executes the real default body, which in turn calls the mock's `output(_:)` — this is why the four existing `TestServiceTests` assertions keep passing without modification.
- `TuistUnitTests` (the CI-referenced scheme) is a Tuist-generated aggregate scheme built from `Module.allCases.flatMap(\.unitTestTargets)` (`Project.swift:123-134`), not a static `.xctestplan` — confirms `TestServiceTests` and the `XcodeBuild*CommandServiceTests` files are both covered by the same `cli-unit-tests` CI job (`.github/workflows/cli.yml`).

## What We're NOT Doing

- **Candidate A** (shared `TestExecutionOrchestrator` extraction, `TestService`/`XcodeBuildTestCommandService` deduplication, the "pre-run server round-trip" unification for quarantine+sharding) — explicitly deferred; ranked #1 by leverage in `research.md` but requires shoring up `XcodeBuildTestCommandServiceTests.swift`'s coverage first and involves a real behavioral decision (the `action != .build` guard divergence in `uploadResultBundleIfNeeded`) that this plan does not make.
- Fixing any of the 8 non-candidate findings from `research.md`'s classification table (untested quarantine continuation, untested `.remote` upload, untested upload error paths, `schemeWithoutTestableTargets`/`unspecifiedPlatform`/`resolveTestProductsPath`/`generateOnly` test gaps, the "wiring-only tests" observation, the unverified shard-plan storage backend) — all explicitly out of scope, unrelated to the three structural candidates being implemented here.
- Redesigning `ShardPlanServicing`'s or `ShardMatrixOutputServicing`'s existing method signatures — only adding one new default-implemented method to the latter.
- Any change to `cli/Sources/TuistServer/OpenAPI/{Types,Client}.swift`/`server.yml` (generated files — out of bounds per root `CLAUDE.md`).

## Implementation Approach

Three independent, additive-then-subtractive phases in ascending order of surface area touched, shipped as one PR (per planning decision): dead-code removal in `TestService.swift` alone → cross-module dedup of the remaining live `passedValue` copies → the OpenAPI-seam closure in the sharding output layer. None of the three phases depends on another's code changes (only their PR ordering is fixed), so if a phase needs to be reverted independently, the other two are unaffected.

Before building/testing any phase, regenerate the relevant targets per repo convention: `tuist generate tuist TuistKit TuistAutomation TuistSupport --no-open` (adjust the target list per phase if narrower regeneration suffices).

## Phase 1: Remove the dead code cluster in TestService.swift

### Overview

Delete the five unreachable destination-parsing helper methods and `TestService`'s own unused copy of `passedValue`. Pure subtraction — every symbol removed here has zero callers anywhere in the repo (verified by both the original research and an independent `ast-grep`/`grep` pass in this session).

### Changes Required:

#### 1. TestService.swift — delete dead methods

**File**: `cli/Sources/TuistKit/Services/TestService.swift`

**Intent**: Remove confirmed-dead, unreachable code to shrink the file and its maintenance surface, with zero behavior change.

**Contract**: Delete `xcodebuildDestination`, `simulatorPlatform`, `xcodebuildPlatform`, `hasConcreteDevice`, `xcodebuildDestinationParameter` (lines 2239-2309) and the file's own unused `passedValue(for:arguments:)` (lines 2170-2175). No other declaration in this file references any of these six methods. `TestService`'s public surface (`run()`, `init`) is unchanged.

### Success Criteria:

#### Automated Verification:

- Build succeeds: `xcodebuild build -workspace Tuist.xcworkspace -scheme tuist CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
- Lint passes: `mise run lint`
- Targeted unit tests pass: `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing TuistKitTests/TestServiceTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
- No orphaned references: `grep -rn "xcodebuildDestination(\|simulatorPlatform(\|xcodebuildPlatform(\|hasConcreteDevice(\|xcodebuildDestinationParameter(" cli/Sources cli/Tests` returns no matches

#### Manual Verification:

- Build the `tuist` CLI and run `tuist test` against a local sample/fixture project; confirm it completes normally with no crash or behavioral change versus pre-change baseline

---

## Phase 2: Deduplicate `passedValue` into a shared TuistSupport utility

### Overview

Replace the three remaining live copies of `passedValue(for:arguments:)` — in `XcodeBuildTestCommandService.swift` and `XcodeBuildBuildCommandService.swift` (`TuistKit`), and `XcodeBuildArgumentParser.swift` (`TuistAutomation`) — with one shared implementation in `TuistSupport`, the common dependency both modules already have.

### Changes Required:

#### 1. New shared utility

**File**: `cli/Sources/TuistSupport/Xcode/XcodeBuildArguments.swift` (new file)

**Intent**: Give the three call sites one canonical implementation of "find the value following an xcodebuild-style `-flag value` argument," instead of three independently maintained copies.

**Contract**: `public func passedValue(for option: String, arguments: [String]) -> String?`, declared at module scope (not nested in a type), body identical to the four existing copies (`firstIndex(of:)` → `index(after:)` → bounds check → subscript). Placed in `TuistSupport/Xcode/` alongside the module's other Xcode-specific utilities (`XcodeController.swift`, `SDKDeploymentTargetsProvider.swift`).

#### 2. XcodeBuildTestCommandService.swift — drop local copy

**File**: `cli/Sources/TuistKit/Services/XcodeBuild/XcodeBuildTestCommandService.swift`

**Intent**: Remove the now-redundant local duplicate.

**Contract**: Delete the `private func passedValue(for:arguments:)` declaration (lines 351-358). Existing call sites (lines 107, 192, 249, 284-285, 320, 342-343) need no edits: the file already `import`s `TuistSupport`, so the unqualified `passedValue(...)` calls resolve to the new module-scope function once the local shadow is gone.

#### 3. XcodeBuildBuildCommandService.swift — drop local copy

**File**: `cli/Sources/TuistKit/Services/XcodeBuild/XcodeBuildBuildCommandService.swift`

**Intent**: Same as above.

**Contract**: Delete the `private func passedValue(for:arguments:)` declaration (lines 289-297). Call sites unchanged, same resolution mechanism.

#### 4. XcodeBuildArgumentParser.swift — drop local copy

**File**: `cli/Sources/TuistAutomation/XcodeBuild/XcodeBuildArgumentParser.swift`

**Intent**: Same as above, closing the cross-module half of the duplication.

**Contract**: Delete the `private func passedValue(for:arguments:)` declaration (lines 48-56). Call sites unchanged, same resolution mechanism.

### Success Criteria:

#### Automated Verification:

- Build succeeds: `xcodebuild build -workspace Tuist.xcworkspace -scheme tuist CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
- Lint passes: `mise run lint`
- Targeted unit tests pass: `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing TuistKitTests/XcodeBuildTestCommandServiceTests -only-testing TuistKitTests/XcodeBuildBuildCommandServiceTests -only-testing TuistAutomationTests/XcodeBuildArgumentParserTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
- Exactly one implementation left: `grep -rln "func passedValue" cli/Sources` returns only the new `TuistSupport` file; `grep -rn "private func passedValue" cli/Sources` returns no matches

#### Manual Verification:

- Build the `tuist` CLI and run both `tuist test` and `tuist xcodebuild test`/`tuist xcodebuild build` locally with explicit passthrough flags (e.g. `-scheme`, `-destination`, `-testProductsPath`) against a sample project; confirm parsed values are picked up identically to pre-change behavior (correct scheme/destination used, nothing silently dropped)

---

## Phase 3: Close the OpenAPI seam in `outputEmptyShardMatrixIfNeeded`

### Overview

Stop `TestService.swift` from constructing the generated `Components.Schemas.ShardPlan` type directly. Add a default-implemented method to `ShardMatrixOutputServicing` that builds the empty placeholder internally and routes through the protocol's existing `output(_:)` requirement, so the four existing tests that verify `output(...)` was called with an empty shape keep passing unmodified.

### Changes Required:

#### 1. ShardMatrixOutputService.swift — add the default `outputEmpty()` operation

**File**: `cli/Sources/TuistKit/Services/Sharding/ShardMatrixOutputService.swift`

**Intent**: Give `ShardMatrixOutputServicing` a no-argument "emit nothing to shard" operation so callers stop needing to hand-construct the generated `Components.Schemas.ShardPlan` type to represent that case.

**Contract**: Add a protocol extension below the `@Mockable protocol ShardMatrixOutputServicing` declaration:

```swift
extension ShardMatrixOutputServicing {
    public func outputEmpty() async throws {
        try await output(
            Components.Schemas.ShardPlan(
                id: "",
                reference: "",
                shard_count: 0,
                shards: [],
                upload_url: ""
            )
        )
    }
}
```

This is a protocol extension with a concrete body, not a new `@Mockable` requirement — it is not regenerated into `MockShardMatrixOutputServicing`. Calling `outputEmpty()` on a mock instance executes this body, which calls the mock's own (already-mockable) `output(_:)`.

#### 2. TestService.swift — switch the call site

**File**: `cli/Sources/TuistKit/Services/TestService.swift`

**Intent**: Stop touching the generated OpenAPI type directly; delegate placeholder construction to the servicing layer.

**Contract**: In `outputEmptyShardMatrixIfNeeded` (lines 1476-1488), replace the direct `shardMatrixOutputService.output(Components.Schemas.ShardPlan(...))` call with `try await shardMatrixOutputService.outputEmpty()`. No other line in the method changes. After this edit, `TestService.swift` has zero occurrences of `Components.Schemas.*`/`Operations.*`.

#### 3. ShardMatrixOutputServiceTests.swift — direct coverage for the new default implementation

**File**: `cli/Tests/TuistKitTests/Services/Sharding/ShardMatrixOutputServiceTests.swift`

**Intent**: Add coverage that exercises `outputEmpty()` against the *concrete* `ShardMatrixOutputService` (not a mock), complementing the four existing indirect assertions in `TestServiceTests.swift`, which only check that `TestService` calls the servicing layer correctly.

**Contract**: One new test using the existing `makeSubject()` fixture helper (`:183`) that calls `fixture.subject.outputEmpty()` and asserts the resulting written matrix has `shard_count == 0` and an empty `shards` array, following the same assertion style as the existing `output_github_writesEmptyMatrixWhenNoShards` test in this file.

### Success Criteria:

#### Automated Verification:

- Build succeeds: `xcodebuild build -workspace Tuist.xcworkspace -scheme tuist CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
- Lint passes: `mise run lint`
- Targeted unit tests pass (including the four pre-existing empty-shard-matrix assertions, unmodified, plus the new direct test): `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing TuistKitTests/TestServiceTests -only-testing TuistKitTests/ShardMatrixOutputServiceTests -only-testing TuistKitTests/ShardPlanServiceTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
- Seam fully closed: `grep -c "Components\.Schemas\.\|Operations\." cli/Sources/TuistKit/Services/TestService.swift` returns `0`

#### Manual Verification:

- Build the `tuist` CLI and run `tuist test --shard-total 2` (or equivalent sharding flags) against a local sample project; confirm the run completes and the shard matrix output is produced correctly, including the empty-matrix early-return path if reachable (e.g. a scheme with no tests to run)

---

## Testing Strategy

### Unit Tests:

- Existing `TestServiceTests`, `XcodeBuildTestCommandServiceTests`, `XcodeBuildBuildCommandServiceTests`, `XcodeBuildArgumentParserTests`, `ShardPlanServiceTests` suites must pass unmodified — none of these three phases changes observable behavior, only where code lives.
- New: one direct test for `ShardMatrixOutputServicing.outputEmpty()` against the concrete service (Phase 3).

### Integration Tests:

- No new integration/acceptance tests added — the existing `TestAcceptanceTests.swift` sharding round-trip tests (`shard_with_remote_test_products`, `shard_with_local_test_products`) already exercise the sharding output path end-to-end and will catch any regression from Phase 3's call-site switch.

### Manual Testing Steps:

1. After Phase 1: run `tuist test` locally, confirm no crash/regression.
2. After Phase 2: run `tuist test` and `tuist xcodebuild test`/`build` with explicit passthrough flags, confirm argument parsing is unaffected.
3. After Phase 3: run `tuist test --shard-total 2`, confirm sharding still completes and produces the expected matrix, including on a scheme with no tests to run if one is available in the sample project.

## Performance Considerations

None — all three changes are structural (code relocation/deletion), not behavioral or algorithmic.

## Migration Notes

Not applicable — no data model, storage, or API-contract changes.

## References

- Research: `context/changes/refactor-opportunities/research.md` (Candidates B and C, ranking, and the "Weryfikacja twierdzeń (ast-grep)" verification section)
- Prior analysis: `context/changes/test-service-analysis/research.md`
- `cli/Sources/TuistKit/Services/TestService.swift:1476-1488,2170-2175,2239-2309`
- `cli/Sources/TuistKit/Services/XcodeBuild/XcodeBuildTestCommandService.swift:351-358`
- `cli/Sources/TuistKit/Services/XcodeBuild/XcodeBuildBuildCommandService.swift:289-297`
- `cli/Sources/TuistAutomation/XcodeBuild/XcodeBuildArgumentParser.swift:48-56`
- `cli/Sources/TuistKit/Services/Sharding/ShardMatrixOutputService.swift:11-13`
- `cli/Tests/TuistKitTests/Services/TestServiceTests.swift:1259,1263,1267,1275,4583,4649-4651`
- `cli/Tests/TuistKitTests/Services/Sharding/ShardMatrixOutputServiceTests.swift:183`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Remove the dead code cluster in TestService.swift

#### Automated

- [ ] 1.1 Build succeeds
- [ ] 1.2 Lint passes
- [ ] 1.3 Targeted unit tests pass (TestServiceTests)
- [ ] 1.4 No orphaned references to the 5 deleted methods

#### Manual

- [ ] 1.5 `tuist test` runs correctly locally, no regression

### Phase 2: Deduplicate passedValue into a shared TuistSupport utility

#### Automated

- [ ] 2.1 Build succeeds
- [ ] 2.2 Lint passes
- [ ] 2.3 Targeted unit tests pass (XcodeBuildTestCommandServiceTests, XcodeBuildBuildCommandServiceTests, XcodeBuildArgumentParserTests)
- [ ] 2.4 Exactly one `passedValue` implementation remains, in TuistSupport

#### Manual

- [ ] 2.5 `tuist test` and `tuist xcodebuild test`/`build` pick up passthrough arguments identically to before

### Phase 3: Close the OpenAPI seam in outputEmptyShardMatrixIfNeeded

#### Automated

- [ ] 3.1 Build succeeds
- [ ] 3.2 Lint passes
- [ ] 3.3 Targeted unit tests pass (TestServiceTests, ShardMatrixOutputServiceTests, ShardPlanServiceTests) including new direct test
- [ ] 3.4 Zero `Components.Schemas.`/`Operations.` occurrences left in TestService.swift

#### Manual

- [ ] 3.5 `tuist test --shard-total 2` completes and produces correct shard matrix output, including empty-matrix path if reachable
