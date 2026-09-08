# Test-service quick-win refactors — Plan Brief

> Full plan: `context/changes/refactor-opportunities/plan.md`
> Research: `context/changes/refactor-opportunities/research.md`

## What & Why

`TestService.swift` (the `tuist test` orchestrator) carries three independent, evidence-verified pieces of structural debt: a confirmed-dead 5-method cluster, a helper function duplicated identically across 4 files/2 modules, and the file's only direct construction of a generated OpenAPI type. All three were ranked, ast-grep-verified, and left for a planning decision by prior research. This plan implements the two lowest-risk, zero-dependency candidates (B and C) — the highest-leverage candidate (A, a shared-orchestrator extraction eliminating `TestService`/`XcodeBuildTestCommandService` duplication) is deliberately deferred.

## Starting Point

`TestService.swift:2239-2309` holds 5 methods with zero callers anywhere in the repo (an incomplete cleanup from a July 2026 commit that removed their only caller chain but not the leaves). `passedValue(for:arguments:)` is duplicated byte-for-byte in `TestService.swift` (unused), `XcodeBuildTestCommandService.swift`, `XcodeBuildBuildCommandService.swift` (all `TuistKit`), and `XcodeBuildArgumentParser.swift` (`TuistAutomation`) — the last copy independently reinvented 13 months after the others despite the file already importing the module holding a working copy. `TestService.swift:1479` hand-builds a generated `Components.Schemas.ShardPlan` value, the file's only direct touch of a generated type; this has needed 4 separate patches over 5 months as the server schema evolved.

## Desired End State

`TestService.swift` shrinks by ~150 lines of dead/duplicated code and stops touching generated OpenAPI types directly. `passedValue` exists exactly once, in `TuistSupport`. All existing tests keep passing unmodified (including the 4 tests asserting empty-shard-matrix behavior — they test behavior, not construction site), plus one new direct test for the new `ShardMatrixOutputServicing.outputEmpty()` method. No user-visible or CLI-behavior change.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Which candidates to implement | B (dead code + passedValue dedup) + C (OpenAPI seam) only; A deferred | A requires shoring up thin test coverage first and a real behavioral decision (guard divergence) this plan doesn't make | Plan |
| Candidate B depth | Both steps (cluster removal + full 4-file dedup) in one plan | Both already verified zero-risk; no reason to split into a future follow-up | Plan |
| Shared `passedValue` shape | Module-scope `public func` in `TuistSupport`, not a `[String]` extension | Zero call-site edits needed — all 3 call sites already `import TuistSupport` and resolve unqualified once the local shadow is deleted | Plan |
| OpenAPI-seam fix shape | Protocol *extension* (`outputEmpty()`) on `ShardMatrixOutputServicing`, not a new `@Mockable` requirement | Extension methods aren't remocked by `@Mockable` — calling it on a test mock falls through to the real body, which calls the mock's `output(_:)`, so all 4 existing tests keep passing unmodified | Plan |
| Rollout | One PR, 3 sequential phases | All 3 changes are independently zero-risk; one review round is enough | Plan |
| Manual QA depth | Automated tests/CI + a local CLI smoke test per phase | Extra confidence at near-zero cost given how mechanical these changes are | Plan |

## Scope

**In scope:**
- Delete the 5-method dead cluster in `TestService.swift` + its own unused `passedValue` copy
- Add one shared `passedValue` implementation to `TuistSupport`; delete the 3 remaining local copies
- Add `ShardMatrixOutputServicing.outputEmpty()`; switch `TestService.swift`'s one direct OpenAPI-construction call site to use it
- One new unit test for `outputEmpty()`

**Out of scope:**
- Candidate A (shared test-execution orchestrator, `TestService`/`XcodeBuildTestCommandService` deduplication)
- Any of the 8 non-candidate findings from research (test-coverage gaps, unverified shard-storage backend)
- Any change to generated OpenAPI files (`Types.swift`, `Client.swift`, `server.yml`)

## Architecture / Approach

Three independent, sequential phases in one PR: (1) pure subtraction of dead code in `TestService.swift`, (2) promote the one still-needed helper to `TuistSupport` (the common ancestor module both `TuistKit` and `TuistAutomation` already depend on) and delete the 3 local shadows, (3) add a protocol-extension default method that internalizes the one generated-type construction `TestService.swift` was doing directly. No phase's code changes depend on another's — only their PR ordering (cluster → dedup → seam) reflects the planning decision.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Remove dead cluster | `TestService.swift` loses 5 unreachable methods + its unused `passedValue` copy | Near-zero — every deleted symbol has zero verified callers |
| 2. Dedup `passedValue` | One `TuistSupport` implementation replaces 4 copies across 2 modules | Near-zero — call sites need no edits, only declaration removal |
| 3. Close OpenAPI seam | `TestService.swift` stops constructing `Components.Schemas.ShardPlan` directly | Low — behavior-preserving by construction (default impl routes through the same mockable `output(_:)`) |

**Prerequisites:** None — all three phases are ready to start immediately, no blocking work.
**Estimated effort:** Small — roughly one focused implementation session across the 3 phases; each phase is a handful of files with mechanical, pre-verified-safe changes.

## Open Risks & Assumptions

- Relies on the `ast-grep`/`grep`-verified claim that none of the deleted/moved symbols have callers outside the files enumerated in research — a final compile + targeted test run in each phase is the actual safety net, not just the prior research.
- Assumes `mise run lint` and the cited `xcodebuild` commands are runnable in the implementer's environment (per root/`cli` `CLAUDE.md` conventions) — no alternative verification path specified.

## Success Criteria (Summary)

- `tuist test`, `tuist xcodebuild test`, and `tuist xcodebuild build` behave identically to before the change (verified by existing + one new automated test, plus a local smoke test per phase)
- `TestService.swift` no longer contains the dead cluster, its own `passedValue` copy, or any direct `Components.Schemas.*`/`Operations.*` reference
- `passedValue` exists exactly once in the codebase, in `TuistSupport`
