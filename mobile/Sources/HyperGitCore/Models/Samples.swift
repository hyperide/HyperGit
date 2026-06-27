// Sample data for SwiftUI previews and unit tests (canned, no network).
import Foundation

extension HGRepo {
    public static let samples: [HGRepo] = [
        HGRepo(id: 1, name: "HyperGit", fullName: "hyperide/HyperGit",
               owner: HGUser(id: 99, login: "hyperide", name: "HyperGit Org",
                             avatarURL: nil, htmlURL: nil),
               description: "Open-source GitHub replacement + local-first mobile app.",
               isPrivate: false, defaultBranch: "main", stargazersCount: 12,
               forksCount: 2, openIssuesCount: 7,
               updatedAt: Date(timeIntervalSinceNow: -3600),
               sshURL: nil, cloneURL: nil,
               htmlURL: URL(string: "https://github.com/hyperide/HyperGit"), language: "Swift"),
    ]
}

extension HGPullRequest {
    public static let samples: [HGPullRequest] = [
        HGPullRequest(id: 10, number: 1, title: "Initialize HyperGit repository",
                      body: "Bootstrap spec, conventions, guardrails.",
                      state: .open, isDraft: false, isMerged: false,
                      author: HGUser(id: 7, login: "agent", name: "HyperGit Agent", avatarURL: nil, htmlURL: nil),
                      head: "feature/init", base: "main", additions: 420, deletions: 0,
                      changedFiles: 5, commits: 1, commentsCount: 0,
                      createdAt: Date(timeIntervalSinceNow: -7200),
                      updatedAt: Date(timeIntervalSinceNow: -3600), mergedAt: nil,
                      htmlURL: URL(string: "https://github.com/hyperide/HyperGit/pull/1")),
    ]
}
