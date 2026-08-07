// Theme — shared colors, metrics, and reusable presentational helpers.
import SwiftUI
import HyperGitCore

enum Theme {
    static let tint = Color(red: 0.30, green: 0.45, blue: 0.92)
    static let mono = Font.system(.footnote, design: .monospaced)

    static func badge(text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

struct PlaceholderView: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(subtitle)
        }
    }
}

struct StateBanner: View {
    let state: LoadState
    var body: some View {
        switch state {
        case .loading: ProgressView()
        case .error(let msg):
            Label(msg, systemImage: "wifi.exclamationmark")
                .font(.footnote).foregroundStyle(.orange)
        case .loaded, .idle:
            EmptyView()
        }
    }
}

/// Shown above a list when it's rendering cache fallback data (the network refresh
/// failed but the local cache had something to show) — so cached content never looks
/// indistinguishable from a fresh fetch (issue #4 acceptance criteria).
struct OfflineBanner: View {
    let reason: String
    var body: some View {
        Label("Showing cached data — \(reason)", systemImage: "icloud.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
    }
}

extension View {
    /// Inline navigation-bar title on iOS; no-op on macOS (cross-platform compile).
    @ViewBuilder
    func inlineNavigationBarTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Cross-platform trailing toolbar placement (.topBarTrailing on iOS, .primaryAction elsewhere).
    static var appTrailing: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }
}
