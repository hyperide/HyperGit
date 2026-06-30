# HyperGit Mobile

Local-first SwiftUI iOS app — offline viewer for GitHub (repos, files, PRs, issues,
commits) and Linear (tickets). Phase 1 MVP per `docs/SPEC.md` §2.

## Layout

```
mobile/
  Package.swift              # HyperGitCore: models, clients, store, cache (swift build/test)
  Sources/HyperGitCore/      # backend-agnostic core library
  Tests/HyperGitCoreTests/   # unit tests (real parsing logic, injected transport)
  App/                       # SwiftUI iOS app target (@main + views)
  project.yml                # xcodegen spec → HyperGit.xcodeproj
```

## Build & Run

Core library + tests (macOS host):

```sh
swift build
swift test --parallel
```

**Run native macOS app** (no Xcode, no Apple account):

```sh
swift run HyperGitApp
```

iOS app (generate the project once, then build for the simulator):

```sh
brew install xcodegen            # one-time dev dependency
xcodegen generate                # from mobile/
xcodebuild -scheme HyperGit -destination 'generic/platform=iOS Simulator' build
# or open HyperGit.xcodeproj in Xcode and run on a simulator
```

## Run

1. Open Settings in the app.
2. Paste a **GitHub** classic PAT (`repo` scope) and/or a **Linear** personal API key.
   OAuth sign-in remains disabled unless a safe public/brokered flow is configured;
   client secrets must not be bundled in the app.
3. Pull to refresh on Repos / Tickets. Everything fetched is cached locally and
   available offline.

## Architecture (SPEC §2.3)

`Views → AppStore (@Observable, @MainActor) → RepositorySource / TicketSource
(protocols) → GitHubClient / LinearClient → CacheStore (MemoryCacheStore; SwiftData
in issue #4)`. The backend is behind `RepositorySource` so GitHub can be swapped for a
HyperGit backend later without touching the UI.
