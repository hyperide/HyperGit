# Term Map

```yaml term-map
entries:
  - term: HyperGit
    domain: product
    definition: Open-source GitHub replacement platform plus local-first SwiftUI mobile client, as defined by docs/SPEC.md.
  - term: Mobile MVP
    domain: mobile
    definition: Current concrete SwiftUI app scope for offline browsing of GitHub and Linear data.
  - term: local-first
    domain: architecture
    definition: Downloaded data remains available offline, with sync handled in the background or on demand.
  - term: RepositorySource
    domain: mobile
    definition: Protocol boundary for repository data providers such as GitHub today and HyperGit later.
  - term: TicketSource
    domain: mobile
    definition: Protocol boundary for unified ticket feeds from GitHub Issues and Linear.
  - term: spec-coverage
    domain: meta-governance
    definition: Scope tag for evidence that supports overall active SpecSection coverage health.
target_ref_aliases:
  - id: docs.SPEC.mobile_scope.law
    definition: docs/SPEC.md section 2 is the governing current SwiftUI mobile app scope.
  - id: docs.SPEC.server_future.admissibility
    definition: docs/SPEC.md keeps backend/platform implementation admissible only as future work for this continuation.
  - id: AGENTS.project_hypergit.deontics
    definition: AGENTS.md project instructions govern spec authority, mobile stack, and review discipline.
  - id: docs.SPEC.mobile_architecture.evidence
    definition: docs/SPEC.md section 2.3 supplies the architecture evidence for the current mobile boundary.
status: draft
```

These draft entries capture the current mobile-only vocabulary used by the active
spec sections and decision records. Promote or revise them during the next full
onboarding pass if the project vocabulary changes.
