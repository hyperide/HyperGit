// HGCheckRun — a CI check run from the GitHub Checks API, associated with a
// commit SHA (typically a PR's head commit). SPEC §2.2 "PR list + details
// (meta, files diff, checks)".
import Foundation

public struct HGCheckRun: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable {
        case queued, inProgress = "in_progress", completed, waiting, pending, requested
    }
    public enum Conclusion: String, Sendable {
        case success, failure, neutral, cancelled, timedOut = "timed_out",
             actionRequired = "action_required", stale, skipped,
             startupFailure = "startup_failure"
    }

    public let id: Int
    public let name: String
    public let status: Status
    public let conclusion: Conclusion?
    public let detailsURL: URL?
    public let startedAt: Date?
    public let completedAt: Date?

    public init(
        id: Int, name: String, status: Status, conclusion: Conclusion?,
        detailsURL: URL?, startedAt: Date?, completedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.detailsURL = detailsURL
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// Overall PR check state, rolled up from individual check runs.
public enum HGChecksSummary: String, Sendable {
    case none, pending, passing, failing

    private static let failingConclusions: Set<HGCheckRun.Conclusion> = [
        .failure, .timedOut, .cancelled, .actionRequired, .startupFailure,
    ]

    public init(runs: [HGCheckRun]) {
        guard !runs.isEmpty else { self = .none; return }
        // A failure wins even while a sibling run is still in progress —
        // reporting "pending" in that case would hide a check that has
        // already failed (a common shape: one job fails fast while another
        // is still building).
        var anyIncomplete = false
        for run in runs {
            // GitHub only ever attaches a `conclusion` once a run has
            // genuinely finished — checked ahead of (not gated behind)
            // `status == .completed` so a run whose raw status string isn't
            // one this build recognizes (falls back to `.queued` in the DTO)
            // still gets its conclusion honored instead of being stuck
            // reading "pending" forever.
            if let conclusion = run.conclusion {
                if Self.failingConclusions.contains(conclusion) {
                    self = .failing
                    return
                }
                continue
            }
            if run.status != .completed { anyIncomplete = true; continue }
            // status == .completed but conclusion == nil: an unrecognized
            // conclusion string GitHub returned. Treat conservatively as a
            // failure rather than defaulting it into the passing bucket.
            self = .failing
            return
        }
        self = anyIncomplete ? .pending : .passing
    }

    public var label: String {
        switch self {
        case .none: return "No checks"
        case .pending: return "Pending"
        case .passing: return "Passing"
        case .failing: return "Failing"
        }
    }
}
