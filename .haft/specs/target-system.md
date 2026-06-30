# Target System Spec

## TS.placeholder.001 Target system placeholder

```yaml spec-section
id: TS.placeholder.001
kind: environment-change
title: Target system placeholder
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

This placeholder only reserves a parseable carrier for onboarding. It is not an active target-system claim.

## TS.hypergit.mobile.000 Mobile offline environment

```yaml spec-section
id: TS.hypergit.mobile.000
spec: target-system
kind: target.environment
title: HyperGit mobile offline environment
statement_type: definition
claim_layer: object
owner: human
status: active
valid_until: 2027-12-31
depends_on: []
supersedes: []
terms: [HyperGit, Mobile MVP, local-first, GitHub, Linear]
target_refs: [docs/SPEC.md#2-hypergit-mobile--swiftui-local-first-the-current-concrete-scope]
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

After sync, the SwiftUI mobile app gives its user an offline-readable local view
of GitHub repositories, pull requests, issues, commits, files, and Linear
tickets that otherwise require live service access.

## TS.hypergit.mobile.001 Mobile MVP focus

```yaml spec-section
id: TS.hypergit.mobile.001
spec: target-system
kind: target.role
title: HyperGit mobile MVP focus
statement_type: definition
claim_layer: description
owner: human
status: active
valid_until: 2027-12-31
depends_on: [TS.hypergit.mobile.000]
supersedes: []
terms: [HyperGit, Mobile MVP, local-first, GitHub, Linear]
target_refs: [docs/SPEC.md#2-hypergit-mobile--swiftui-local-first-the-current-concrete-scope]
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

For current implementation work, HyperGit focuses on the SwiftUI mobile MVP described
in `docs/SPEC.md` section 2: offline-capable browsing of GitHub repositories, files,
pull requests, issues, commits, and Linear tickets. Backend/platform work remains in
the master spec and tasks, but it is not the current coding focus.

## TS.hypergit.mobile.boundary.001 Mobile implementation boundary

```yaml spec-section
id: TS.hypergit.mobile.boundary.001
spec: target-system
kind: target.boundary
title: Mobile implementation boundary
statement_type: admissibility
claim_layer: description
owner: human
status: active
valid_until: 2027-12-31
depends_on: [TS.hypergit.mobile.001]
supersedes: []
terms: [Mobile MVP, GitHub, Linear]
target_refs:
  - docs.SPEC.mobile_scope.law
  - docs.SPEC.server_future.admissibility
  - AGENTS.project_hypergit.deontics
  - docs.SPEC.mobile_architecture.evidence
evidence_required:
  - kind: manual
    ref: spec-diff-when-behavior-changes
    description: Review changed paths and spec diff when intended behavior changes.
```

The current implementation boundary is the mobile app. Server-side HyperGit
platform work remains specified for later phases but is outside the active coding
surface for this continuation.

## TS.hypergit.mobile.002 Source abstraction

```yaml spec-section
id: TS.hypergit.mobile.002
spec: target-system
kind: target.boundary
title: Mobile source abstraction
statement_type: duty
claim_layer: work
owner: human
status: draft
valid_until: 2027-12-31
depends_on: [TS.hypergit.mobile.boundary.001]
supersedes: []
terms: [RepositorySource, TicketSource, GitHub, Linear]
target_refs: [docs/SPEC.md#24-multiple-backends]
evidence_required:
  - kind: L3
    ref: unit-tests
    description: Source abstraction behavior is covered by Swift tests.
    command: swift test
```

GitHub and Linear clients must remain behind source protocols so the UI can keep
working when GitHub is later swapped for HyperGit, and so tests can exercise parsing
and pagination without live network calls.
