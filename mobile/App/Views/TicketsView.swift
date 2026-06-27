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
                    ToolbarItem(placement: .topBarTrailing) {
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
            default:
                if store.tickets.isEmpty {
                    PlaceholderView(icon: "ticket",
                                    title: "No tickets",
                                    subtitle: "Add a Linear API key in Settings to pull your issues.")
                } else {
                    List(store.tickets) { ticket in TicketRow(ticket: ticket) }
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
