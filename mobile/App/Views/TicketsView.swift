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
                    List(store.tickets) { ticket in
                        NavigationLink(value: ticket) { TicketRow(ticket: ticket) }
                    }
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
        // Registered unconditionally (mirrors IssuesView/IssueDetailView): a pushed
        // detail view must keep resolving even if `store.tickets` later becomes empty
        // or errors on a refresh triggered while the detail view is on screen.
        .navigationDestination(for: HGTicket.self) { ticket in
            TicketDetailView(ticket: ticket)
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

struct TicketDetailView: View {
    let ticket: HGTicket

    var body: some View {
        List {
            headerSection
            if ticket.team != nil || ticket.assignee != nil || ticket.updatedAt != nil {
                metaSection
            }
            if let url = ticket.url {
                Section {
                    Link("Open in \(ticket.source == .linear ? "Linear" : "GitHub")", destination: url)
                }
            }
        }
        .navigationTitle(ticket.identifier)
        .inlineNavigationBarTitle()
    }

    private var headerSection: some View {
        Section {
            Text(ticket.title).font(.headline)
            HStack(spacing: 8) {
                Theme.badge(text: ticket.source.rawValue.capitalized,
                            color: ticket.source == .linear ? .teal : .indigo)
                Theme.badge(text: ticket.stateName)
            }
            if !ticket.labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Labels are plain strings (no server-side id), and duplicate
                        // names within one ticket aren't ruled out by either source's
                        // API — key by index instead of `\.self` so a dupe can't
                        // collide into one dropped/glitched row. Iterating `.indices`
                        // (vs. wrapping `.enumerated()` in an `Array`) avoids an
                        // allocation on every body evaluation.
                        ForEach(ticket.labels.indices, id: \.self) { index in
                            Theme.badge(text: ticket.labels[index])
                        }
                    }
                }
            }
        }
    }

    private var metaSection: some View {
        Section {
            if let team = ticket.team {
                LabeledContent("Team", value: team)
            }
            if let assignee = ticket.assignee {
                LabeledContent("Assignee", value: assignee.displayName)
            }
            if let updated = ticket.updatedAt {
                LabeledContent("Updated", value: updated.formatted(.relative(presentation: .named)))
            }
        }
    }
}
