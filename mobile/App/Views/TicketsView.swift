// Tickets tab — unified inbox across Linear and GitHub issues (SPEC §2.2).
import SwiftUI
import HyperGitCore

struct TicketsTab: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        NavigationStack {
            TicketsView()
                .navigationTitle("Tickets")
                .toolbar {
                    ToolbarItem(placement: .appTrailing) {
                        Button {
                            Task { await store.loadTickets() }
                        } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
        }
    }
}

struct TicketsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Group {
            switch store.ticketsState {
            case .loading where store.tickets.isEmpty:
                ProgressView("Loading tickets…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message) where store.tickets.isEmpty:
                ContentUnavailableView {
                    Label("Could not load tickets", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            default:
                if store.tickets.isEmpty {
                    PlaceholderView(icon: "ticket",
                                    title: "No tickets",
                                    subtitle: "Add a Linear API key in Settings to pull your issues.")
                } else {
                    List(store.tickets) { ticket in TicketRow(ticket: ticket) }
                        .refreshable { await store.loadTickets() }
                        .safeAreaInset(edge: .top) {
                            // `ticketsStaleReason` and `.error` are mutually exclusive
                            // (AppStore only sets one at a time), so this shows exactly
                            // one banner: the stale-cache reason on a clean `.loaded`, or
                            // the failure message when `.error` still has cached tickets
                            // to fall back to. Without the `.error` branch here, a hard
                            // failure with non-empty tickets would show no indicator at
                            // all — the previous inline error `Text` this replaced.
                            if let reason = store.ticketsStaleReason {
                                OfflineBanner(reason: reason)
                            } else if case .error(let message) = store.ticketsState {
                                OfflineBanner(reason: message)
                            }
                        }
                }
            }
        }
        .task { if store.tickets.isEmpty { await store.loadTickets() } }
    }
}

struct TicketRow: View {
    let ticket: HGTicket
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(ticket.identifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                Theme.badge(text: ticket.source.rawValue.capitalized,
                            color: ticket.source == .linear ? .teal : .indigo)
                Spacer()
                Theme.badge(text: ticket.stateName)
            }
            Text(ticket.title).font(.body.weight(.medium)).lineLimit(2)
            if let team = ticket.team {
                Text(team).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
