# Enabling System Spec

## ES.placeholder.001 Enabling system placeholder

```yaml spec-section
id: ES.placeholder.001
kind: creator-role
title: Enabling system placeholder
statement_type: explanation
claim_layer: carrier
owner: human
status: draft
valid_until: null
depends_on: []
supersedes: []
terms: []
target_refs: []
evidence_required: []
```

This placeholder only reserves a parseable carrier for onboarding. It is not active enabling-system governance.

## ES.hypergit.mobile.000 Mobile enabling architecture

```yaml spec-section
id: ES.hypergit.mobile.000
spec: enabling-system
kind: enabling.architecture
title: Mobile enabling architecture
statement_type: definition
claim_layer: work
owner: human
status: active
valid_until: 2027-12-31
depends_on: [TS.hypergit.mobile.boundary.001]
supersedes: []
terms: [Mobile MVP, Swift Testing, review]
target_refs: [AGENTS.md, docs/SPEC.md#23-mobile-architecture-mvp]
evidence_required:
  - kind: L3
    ref: swift-build
    description: Swift package builds successfully from mobile/.
    command: swift build
  - kind: L3
    ref: swift-test
    description: SwiftPM test suite passes from mobile/.
    command: swift test
```

The enabling system for the active work is the repository-local agent workflow
that reads the master spec, changes the SwiftUI mobile package, verifies it with
SwiftPM checks, and records reviewable evidence before commit.

## ES.hypergit.mobile.001 Verification policy

```yaml spec-section
id: ES.hypergit.mobile.001
spec: enabling-system
kind: enabling.evidence_policy
title: Mobile verification policy
statement_type: duty
claim_layer: work
owner: human
status: draft
valid_until: 2027-12-31
depends_on: [ES.hypergit.mobile.000]
supersedes: []
terms: [Swift Testing, swift build, swift test, review]
target_refs: [AGENTS.md, docs/SPEC.md#23-mobile-architecture-mvp]
evidence_required:
  - kind: L3
    ref: swift-build
    description: Swift package builds successfully from mobile/.
    command: swift build
  - kind: L3
    ref: swift-test
    description: SwiftPM test suite passes from mobile/.
    command: swift test
  - kind: manual
    ref: review-diff
    description: External review CLI runs before commit.
    command: review diff -C .
```

Mobile changes must be verified with `swift build` and the SwiftPM test suite.
Diff review is required before commits. User-visible UI changes require rendered
evidence when the target can produce a window or simulator screenshot.

## ES.hypergit.mobile.002 Spec authority

```yaml spec-section
id: ES.hypergit.mobile.002
spec: enabling-system
kind: enabling.runtime_policy
title: Master spec authority
statement_type: duty
claim_layer: carrier
owner: human
status: draft
valid_until: 2027-12-31
depends_on: [ES.hypergit.mobile.000]
supersedes: []
terms: [master spec, behavior change]
target_refs: [docs/SPEC.md]
evidence_required:
  - kind: manual
    ref: spec-diff-when-behavior-changes
    description: Update docs/SPEC.md when a change alters intended behavior.
```

`docs/SPEC.md` remains the product source of truth. If implementation changes intended
behavior, update that file in the same change; otherwise keep code changes scoped to
the existing spec.
