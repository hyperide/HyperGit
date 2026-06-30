# Workflow

## Intent

Haft should bias toward small reversible changes, require explicit decisions for core/domain edits,
and always verify behavior with tests or concrete runtime evidence before calling work complete.

## Defaults

```yaml
mode: standard
require_decision: true
require_verify: true
allow_autonomy: false
```

## Setup

Run `.haft/bin/install-codex-mcp` once in a Codex environment to register the
Haft MCP server in the supported global Codex config. The installer writes a
small generated wrapper under `~/.local/share/hypergit/haft-mcp/` and registers
that path, so the global Codex MCP entry does not execute a mutable script from
the checkout. Re-run the installer after moving the checkout. The checked-in
OpenCode entry documents the local wrapper but stays disabled by default; enable
it only in a trusted local checkout.

On a fresh clone, run `.haft/bin/bootstrap-local-state` before relying on
`haft check`; it records SpecSection baselines, runs the current mobile/tooling
verification commands, and only then attaches local evidence. Haft stores
baselines and attached evidence in the operator-local SQLite database, while
the checked-in markdown files remain the portable source carriers. Use
`.haft/bin/test-bootstrap-local-state` to exercise the bootstrap twice in an
isolated `HOME` against the installed Haft binary. CI runs that real bootstrap
path on a self-hosted macOS runner labeled `haft` with pinned Haft `7.0.0`
(`a80902c`) only when the workflow ref is `main`, for `main` push events or
explicit manual dispatch of `main`; pull
requests must not execute PR-controlled scripts on the self-hosted runner. The
stubbed bootstrap check only covers wrapper behavior and must not be treated as
semantic coverage.

## Client Invocation Syntax

Codex skill files use `$h-*` because Codex skills are explicitly invoked with
dollar-prefixed names. OpenCode command files use `/h-*` because OpenCode exposes
the same operator actions as slash commands. Treat them as client-specific entry
syntax for the same Haft workflow, not as interchangeable literals.

## Draft Spec Sections

Only active SpecSections are CI/governance requirements for this bootstrap.
Draft sections can describe future manual evidence policy, but they do not become
blocking obligations until they are promoted to `status: active` and have a
defined carrier or external process for recording the manual evidence. A
`valid_until` value on a draft section is planning freshness metadata for the
draft itself, not an active governance expiry.

## Autonomy Boundary

This repository does not enable autonomous execution through checked-in config,
environment variables, or CI. `allow_autonomy: false` is the default. If a client
surface exposes a session-level autonomous mode, treat that as external operator
state and require an explicit in-session signal from the client/user before using
the autonomous path; absent that signal, stop at the compare/decide boundary.

This bootstrap is intentionally partial: it verifies the current mobile/tooling
slice and does not claim full project onboarding readiness. Use
`haft spec onboard --json` as the authoritative check for remaining onboarding
phases. Baselines are lifecycle state, not a one-time setup artifact: `haft spec
check` can report drift after carrier edits, and intentional drift must be
rebaselined explicitly with `HAFT_BOOTSTRAP_REBASELINE=1` plus a non-empty
`HAFT_BOOTSTRAP_REBASELINE_REASON`. Do not set those rebaseline variables in
automatic CI; rebaseline is a human-triggered operator action for reviewed drift.

## Path Policies

```yaml
- path: "mobile/**"
  mode: standard
  require_decision: true
  require_verify: true
- path: "docs/**"
  mode: standard
  require_decision: true
  require_verify: true
- path: "ci/**"
  mode: standard
  require_decision: true
  require_verify: true
- path: "server/**"
  status: deferred
  mode: standard
  require_decision: true
  require_verify: true
  activation: separate server-scoped DecisionRecord and verification path
- path: ".haft/**"
  mode: standard
  require_decision: true
  require_verify: true
- path: ".agents/**"
  mode: standard
  require_decision: true
  require_verify: true
- path: ".opencode/**"
  mode: standard
  require_decision: true
  require_verify: true
- path: "opencode.json"
  mode: standard
  require_decision: true
  require_verify: true
- path: ".serena/**"
  mode: standard
  require_decision: true
  require_verify: true
```

`server/**` is listed because future server work should also use standard Haft
governance. The current bootstrap/CI path in this change is narrower: it is a
mobile/tooling continuation and deliberately rejects mixed `server/**` changes
until a separate server-scoped decision and verification path exists.

Reasoning-gate quality is a human/review responsibility. CI validates the
persisted fields that make the gate auditable (`counterargument`,
`weakest_link`, `why_not_others`, predictions, rollback triggers), but it cannot
prove an agent's private reasoning quality from static carriers alone.

## Exceptions

Use tactical mode for narrow test-only fixes or low-risk docs updates. When a change touches a
policy-heavy path, keep the decision explicit even if the code delta is small.
