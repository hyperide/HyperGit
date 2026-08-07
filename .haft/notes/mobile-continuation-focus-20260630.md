---
id: note-20260630-mobile-continuation-focus
kind: Note
version: 1
status: active
title: Mobile continuation focus
mode: tactical
created_at: 2026-06-30T15:24:30Z
updated_at: 2026-06-30T16:20:30Z
---

# Mobile Continuation Focus

The continuation preserves the prior session context without committing raw
chat logs or session-specific identifiers. The active implementation focus is
the SwiftUI mobile app only: GitHub and Linear data access, offline-friendly app
behavior, auth wiring, and mobile verification. Backend/platform work remains in
`docs/SPEC.md` and the task tracker, but it is not the current coding surface.

Raw session logs are kept as local ignored evidence outside git. The durable
public carrier records only the actionable focus needed by future agents.
