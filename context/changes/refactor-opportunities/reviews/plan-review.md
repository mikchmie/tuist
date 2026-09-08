<!-- PLAN-REVIEW-REPORT -->
# Plan Review: Test-service quick-win refactors

- **Plan**: `context/changes/refactor-opportunities/plan.md`
- **Mode**: Deep
- **Date**: 2026-09-08
- **Verdict**: REVISE → SOUND (after triage; all 5 findings fixed)
- **Findings**: 1 critical, 3 warnings, 1 observation

## Verdicts

| Dimension | Verdict (at review) | After fixes |
|-----------|---------------------|-------------|
| End-State Alignment | WARNING | PASS |
| Lean Execution | PASS | PASS |
| Architectural Fitness | WARNING | PASS |
| Blind Spots | FAIL | PASS |
| Plan Completeness | WARNING | PASS |

## Grounding

13/13 paths ✓, 11/11 symbols ✓, brief↔plan ✓.
Nit (not a finding): the plan cites `Package.swift:1340`/`:1480`; the file is at repo root, not `cli/Package.swift`. Both cited lines do contain `"TuistSupport"`, so the dependency claim holds.

Verified clean and left alone:
- All five dead methods (`TestService.swift:2239-2309`) have zero callers outside each other.
- `simulatorController` (`:1871, :2084-2096`) and `XcodeBuildDestination.find` (`:1837, :1864`) stay live elsewhere — Phase 1 leaves no orphaned dependency.
- `xcodebuildPlatformDestination` is correctly *not* in the delete list (still used at `:980, :2204`).
- All four `passedValue` files import `TuistSupport`; every call is unqualified; zero `self.passedValue`. Phase 2's name-resolution mechanism is sound.
- `TestServiceTests.swift:4649-4651` is `verify(shardMatrixOutputService).output(.matching { $0.shard_count == 0 && $0.shards.isEmpty })` — a protocol-extension `outputEmpty()` routes straight through it, as the plan claims.
- `TestService.swift` has exactly one `Components.Schemas.` occurrence.
- All four cited test suites exist.

## Findings

### F1 — Phase 3's manual verification command cannot run

- **Severity**: ❌ CRITICAL
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Blind Spots
- **Location**: Phase 3 → Manual Verification; Testing Strategy step 3; Progress step 3.5
- **Detail**: The plan prescribes `tuist test --shard-total 2`, which throws `TestServiceError.shardPlanningRequiresBuildOnly` before doing anything (`TestService.swift:264-266`) — sharding requires `--build-only` (`TestRunCommand.swift:261, :402`). Compounding it, `outputEmptyShardMatrixIfNeeded` is called from exactly one place, `finishSkippedTests` (`TestService.swift:1455`), the "nothing to test" path; a sharded build that has tests never reaches it. Phase 3 is the only phase touching runtime behavior and this was its only manual gate.
- **Fix A ⭐ Recommended**: Correct to `tuist test --build-only --shard-total 2` against a no-test-targets fixture.
  - Strength: Minimal reproduction of the changed line.
  - Tradeoff: Requires picking/creating such a fixture locally.
  - Confidence: HIGH — guard, flag, and single call site read directly from source.
  - Blind spot: Whether a suitable sample project exists locally is unverified.
- **Fix B**: Drop the manual step; rely on existing automated coverage.
  - Strength: Four `TestServiceTests` assertions (`:1260, 1264, 1268, 1276` → `:4649`) already cover this exact path with the exact asserted shape, plus the new `ShardMatrixOutputServiceTests` test and the `TestAcceptanceTests` sharding round-trip.
  - Tradeoff: No end-to-end human eyeball on sharding output.
  - Confidence: HIGH — coverage confirmed in source.
  - Blind spot: None significant.
- **Decision**: FIXED via Fix B — Phase 3's Manual Verification replaced with an explicit "none, and why" note; Testing Strategy step 3 rewritten; Progress `#### Manual` subsection and step 3.5 removed. Consistency propagated to Desired End State and to `plan-brief.md` (Manual QA depth row, Success Criteria).

### F2 — Phase 3's stated motivation isn't what the fix delivers

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: End-State Alignment
- **Location**: `plan-brief.md` "Starting Point"; Phase 3 Overview
- **Detail**: The brief justified Phase 3 with "this has needed 4 separate patches over 5 months as the server schema evolved." Moving the five-field `Components.Schemas.ShardPlan` literal from `TestService.swift:1479` into `ShardMatrixOutputService.swift` does not reduce that — the next required-field addition still means editing one struct literal, just in a different file. The real benefit is narrower (locality/layering), and the measurable success criterion (`grep -c … == 0`) passes either way, so nothing in the plan caught the gap. CLAUDE.md requires PR descriptions to preserve reasoning, so shipping this rationale would overclaim.
- **Fix**: Restate the benefit as layering/locality in both `plan.md` Phase 3 Overview and `plan-brief.md` Starting Point.
  - Strength: Keeps a legitimate change while the PR description stays accurate.
  - Tradeoff: Weakens the case for Phase 3 — worth confirming it still clears the bar.
  - Confidence: HIGH — before/after maintenance cost directly comparable.
  - Blind spot: The "4 patches over 5 months" claim comes from prior research, not re-derived from git history here.
- **Decision**: FIXED — added a "What this does and does not buy" paragraph to Phase 3; rewrote the brief's Starting Point sentence.

### F3 — Progress phase headings don't match the plan body

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Plan Completeness
- **Location**: `## Progress` → Phase 2 and Phase 3 headings
- **Detail**: `progress-format.md` requires `### Phase N: <name>` matching the `## Phase N:` headers. Two dropped backticks (`Deduplicate passedValue …`, `… seam in outputEmptyShardMatrixIfNeeded`), which a strict matcher in `/10x-implement` would fail on. Everything else in the contract was clean: one `## Progress` after `## References`, correct `#### Automated`/`#### Manual` subdivision, indices matched to Success Criteria bullets, no stray checkboxes in Phase blocks.
- **Fix**: Add the backticks so both headings match verbatim.
- **Decision**: FIXED — all three `## Phase N:` / `### Phase N:` pairs now match exactly.

### F4 — New public TuistSupport API ships with no direct test

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Plan Completeness
- **Location**: Phase 2 → Testing Strategy
- **Detail**: Phase 3 adds a direct test for its new API; Phase 2 added a new `public func` to a module the whole CLI imports and added none, despite `cli/Tests/TuistSupportTests/` existing. The three consumer suites cover the helper only incidentally via `-scheme`/`-testProductsPath` passthrough; neither nil branch — option absent, and option is the last element (`arguments.endIndex > valueIndex`) — is exercised anywhere. The trailing-flag branch is the one a future "simplification" would silently break.
- **Fix**: Add `XcodeBuildArgumentsTests.swift` with three cases (value present, option absent, option trailing); add to Phase 2's automated criteria and Progress.
- **Decision**: FIXED — added as Phase 2 change item #5, added to the Phase 2 `-only-testing` command, added to Testing Strategy, and recorded as Progress step 2.6.

### F5 — Generic global name in a universally-imported module

- **Severity**: 💭 OBSERVATION
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Architectural Fitness
- **Location**: Phase 2 → new shared utility file
- **Detail**: `public func passedValue(for:arguments:)` at module scope is visible in every file importing `TuistSupport` — nearly the whole CLI. Free-function precedent exists (`Utils/Functions.swift`, `Utils/GraphAlgorithms.swift`, 8 total) but those are generic combinators in `Utils/`; the plan placed a domain-specific xcodebuild parser in `Xcode/`, a directory holding only types. The module-scope choice was deliberate (it is what makes ~20 call sites need zero edits) — this flags the cost, not the call.
- **Fix A ⭐ Recommended**: Keep module scope, move to `TuistSupport/Utils/`.
  - Strength: Preserves the zero-call-site-edit property while matching where free functions already live.
  - Tradeoff: Slightly less discoverable than an `Xcode/` grouping.
  - Confidence: HIGH — placement convention read from the existing free-function files.
  - Blind spot: None significant.
- **Fix B**: Scope as a `[String]` extension (`arguments.passedValue(for:)`).
  - Strength: No global namespace pollution; better-reading call site.
  - Tradeoff: ~20 mechanical call-site edits; reverses a settled decision.
  - Confidence: MEDIUM — mechanical, but re-opens a settled choice.
  - Blind spot: None significant.
- **Decision**: FIXED via Fix A — source moved to `cli/Sources/TuistSupport/Utils/XcodeBuildArguments.swift`, test to `cli/Tests/TuistSupportTests/Utils/XcodeBuildArgumentsTests.swift`, with the accepted cost of module scope documented inline in the plan.
