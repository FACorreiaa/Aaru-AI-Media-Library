import SwiftUI

/// Find leagues, teams and players to follow (SPT-002): type two letters or more, narrow by
/// kind, and follow or unfollow from the row. Before anything is typed, the fixed picks.
struct SportsSearchView: View {
    let model: SportsModel

    /// The search scope: everything, or one kind.
    private enum Scope: String, CaseIterable, Identifiable {
        case all, league, team, player

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .all: "All"
            case .league: "Leagues"
            case .team: "Teams"
            case .player: "Players"
            }
        }

        var kind: SportEntityKind? {
            switch self {
            case .all: nil
            case .league: .league
            case .team: .team
            case .player: .player
            }
        }
    }

    private struct Query: Equatable {
        let text: String
        let scope: Scope
    }

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var scope: Scope = .all
    @State private var results: [SportEntity] = []
    @State private var searched: Query?
    @State private var isSearching = false
    @State private var failed = false

    private static let minimum = 2

    private var query: Query {
        Query(text: text.trimmingCharacters(in: .whitespacesAndNewlines), scope: scope)
    }

    var body: some View {
        NavigationStack {
            List {
                if query.text.count < Self.minimum {
                    Section {
                        ForEach(model.suggestions, id: \.followKey) { entity in
                            SportEntityRow(entity: entity, model: model)
                        }
                    } header: {
                        if !model.suggestions.isEmpty {
                            Text("Start with a league")
                        }
                    }
                } else {
                    ForEach(results, id: \.followKey) { entity in
                        SportEntityRow(entity: entity, model: model)
                    }
                }
            }
            .paperPage()
            .overlay { overlay }
            #if os(iOS)
                .searchable(
                    text: $text, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Leagues, teams, players"
                )
                .navigationBarTitleDisplayMode(.inline)
            #else
                .searchable(text: $text, prompt: "Leagues, teams, players")
            #endif
                .searchScopes($scope) {
                    ForEach(Scope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .task { await model.loadSuggestions() }
                .task(id: query) { await search(query) }
                .navigationTitle("Find in Sports")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        ProblemBanner(message: model.problem) { model.problem = nil }
                        SportsCredit()
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    @ViewBuilder private var overlay: some View {
        if query.text.count < Self.minimum {
            if model.suggestions.isEmpty {
                ContentUnavailableView(
                    "Find a league or a team",
                    systemImage: "sportscourt",
                    description: Text("Search by name: the Premier League, the Lakers, a fighter.")
                )
            }
        } else if failed {
            ContentUnavailableView(
                "Sports search isn't answering",
                systemImage: "wifi.exclamationmark",
                description: Text("Try again in a moment.")
            )
        } else if results.isEmpty, isSearching || searched != query {
            ProgressView()
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query.text)
        }
    }

    private func search(_ query: Query) async {
        guard query.text.count >= Self.minimum else {
            results = []
            searched = nil
            failed = false
            return
        }
        // A pause after the last keystroke; typing on cancels this and starts again.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        let found = await model.search(query.text, kind: query.scope.kind)
        guard !Task.isCancelled else { return }
        failed = found == nil
        results = found ?? []
        searched = query
    }
}

/// A league, team or player with Follow / Following.
private struct SportEntityRow: View {
    let entity: SportEntity
    let model: SportsModel

    var body: some View {
        let following = model.isFollowing(entity)
        HStack(spacing: 12) {
            SportBadge(url: entity.badgeUrl, sport: entity.sport, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name)
                    .foregroundStyle(Color(.ink))
                Text(entity.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if model.changing.contains(entity.followKey) {
                ProgressView().controlSize(.small)
            }
            if following {
                Button("Following") { toggle(to: false) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Following \(entity.name)")
                    .accessibilityHint("Unfollows")
            } else {
                Button("Follow") { toggle(to: true) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Follow \(entity.name)")
            }
        }
        .disabled(model.changing.contains(entity.followKey))
    }

    private func toggle(to follow: Bool) {
        Task { await model.setFollowing(entity, follow) }
    }
}
