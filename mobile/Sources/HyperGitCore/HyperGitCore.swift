// HyperGitCore — umbrella module.
// Re-exports nothing synthetic; this file documents the module's public surface.
// Public types are declared `public` across the subfolders and are visible
// automatically to the iOS app target that imports HyperGitCore.

import Foundation

/// Top-level namespace marker. The module's public API is composed of:
/// - Models:            HGUser, HGRepo, HGFileEntry, HGFileContent, HGCommit,
///                       HGLabel, HGIssue, HGPullRequest, HGTicket, HGDiff*, HGFileChange.
/// - Networking:        HTTPTransport, HTTPClient, HTTPError.
/// - Auth:              TokenKey, TokenStore, KeychainTokenStore.
/// - Clients:           RepositorySource, TicketSource, GitHubClient, LinearClient.
/// - Cache:             CacheStore, MemoryCacheStore.
/// - Store:             AppStore, LoadState.
public enum HyperGitCore {
    /// Semantic version of the core library. Bump on release.
    public static let version = "0.1.0"
}
