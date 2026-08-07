---
id: dec-20260630-spec-plan-001-6ba09fda
kind: DecisionRecord
version: 1
status: active
title: Keep the implementation boundary on the SwiftUI app
mode: standard
valid_until: 2027-12-31
affected_files:
  - mobile/**
  - docs/SPEC.md
  - .haft/specs/target-system.md
evidence_requirements:
  - git diff --cached --name-only
  - swift build
  - swift test
selected_title: SwiftUI app implementation boundary
why_selected: It prevents accidental backend scope creep and gives agents a clear boundary for commits, review, and verification.
selection_policy: Honor the user's app-only focus and the repo's spec authority while keeping future backend work visible but inactive.
counterargument: Some mobile abstractions are designed for future HyperGit backend replacement, so backend assumptions can leak into app work.
why_not_others:
  - title: Implement server scaffolding now
    reason: It is outside the current focus and would dilute mobile verification.
  - title: Remove backend references entirely
    reason: The master spec still needs to preserve future platform direction.
weakest_link: The boundary fails if shared abstractions start encoding unimplemented server behavior instead of mobile-provider contracts.
refresh_triggers:
  - A required mobile feature cannot be expressed without changing platform scope.
  - The user opens a backend-focused implementation phase.
predictions:
  - claim: Active implementation changes remain inside the mobile app and repo-local tooling.
    observable: git diff --cached --name-only
    threshold: no server implementation files are changed
rollback:
  triggers:
    - A mobile feature requires active server implementation.
    - The user changes the active focus to backend/platform work.
  steps:
    - Reopen the mobile boundary section.
    - Create a server/platform boundary decision before implementation.
created_at: 2026-06-30T15:20:16Z
updated_at: 2026-06-30T15:32:30Z
links:
  - ref: TS.hypergit.mobile.boundary.001
    type: governs
---

# Keep the implementation boundary on the SwiftUI app

## 1. Problem Frame

HyperGit has platform and mobile goals, but this continuation must not mix server
implementation with the requested app work.

## 2. Decision

**Selected:** Keep the active coding boundary on `mobile/**`; represent server/platform work in `docs/SPEC.md` and future tasks, not in this implementation slice.

**Selection policy:** Honor the user's app-only focus and the repo's spec authority while keeping future backend work visible but inactive.

**Why selected:** It prevents accidental backend scope creep and gives agents a clear boundary for commits, review, and verification.

**Spec sections:**
- TS.hypergit.mobile.boundary.001

## 3. Rationale

**Counterargument:** Some mobile abstractions are designed for future HyperGit backend replacement, so backend assumptions can leak into app work.

**Selected variant weakest link:** The boundary fails if shared abstractions start encoding unimplemented server behavior instead of mobile-provider contracts.

**Rejected alternatives:**
| Variant | Verdict | Reason |
|---------|---------|--------|
| Implement server scaffolding now | Rejected | It is outside the current focus and would dilute mobile verification. |
| Remove backend references entirely | Rejected | The master spec still needs to preserve future platform direction. |

**Evidence requirements:**
- `git diff --cached --name-only`
- `swift build`
- `swift test`

## 4. Consequences

**Rollback plan:**
Triggers:
- A required mobile feature cannot be expressed without changing platform scope.
- The user opens a backend-focused implementation phase.

**Refresh triggers:**
- New tickets or spec changes move active work from mobile to server/platform.
