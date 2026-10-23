import AaruAPI
import SwiftUI

/// Achievements (GAM-001…004, DESIGN.md §17): level and points to the next level, the streak,
/// then the badges by family, and "How you earned it". Not a destination: pushed from Home's
/// strip, Friends' "You" card and Insights.
struct AchievementsView: View {
    let model: ProgressModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AaruSpace.section) {
                if let progress = model.progress {
                    LevelHeader(progress: progress)
                    StreakBar(progress: progress, showsLevel: false)
                    NavigationLink {
                        PointsHistoryView(model: model)
                    } label: {
                        Label("How you earned it", systemImage: "list.bullet.rectangle")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(.accent))
                }
                if model.hasLoadedBadges {
                    BadgeShelf(badges: model.badges)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.paper))
        .navigationTitle("Achievements")
        .task {
            async let progress: Void = model.refresh()
            async let badges: Void = model.loadBadges()
            _ = await (progress, badges)
        }
        .refreshable {
            await model.refresh()
            await model.loadBadges()
        }
        .safeAreaInset(edge: .bottom) {
            ProblemBanner(message: model.problem) { model.problem = nil }
        }
    }
}

/// "Level 4" in the serif, the total, and the bar to the next level.
private struct LevelHeader: View {
    let progress: AchievementProgress

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            Text("Level \(progress.level)")
                .font(.aaruDisplay(.largeTitle, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("\(progress.total.formatted()) points · \(progress.weekPoints.formatted()) this week")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color(.muted))
            LevelLine(progress: progress)
        }
    }
}

/// The points ledger, newest first (`GET /v1/me/points`). A take-back reads as such.
struct PointsHistoryView: View {
    let model: ProgressModel

    var body: some View {
        List {
            if model.points.isEmpty {
                Text("Points arrive as you tick episodes, finish titles and watch with friends.")
                    .foregroundStyle(Color(.muted))
            }
            ForEach(model.points, id: \.id) { event in
                PointsRow(event: event)
            }
            if model.pointsNext != nil {
                Button("Earlier") { Task { await model.loadPoints(more: true) } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle("How you earned it")
        .task { await model.loadPoints() }
        .refreshable { await model.loadPoints() }
    }
}

private struct PointsRow: View {
    let event: PointsEventItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PointsWords.kind(event.kind, revocation: event.revocation))
                if let title = event.title {
                    Text(title.title)
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
                Text(ActivityWords.day(event.day))
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
            }
            Spacer(minLength: 8)
            Text(event.points > 0 ? "+\(event.points)" : "\(event.points)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(event.points < 0 ? Color(.muted) : Color(.ink))
        }
        .accessibilityElement(children: .combine)
    }
}

/// What each kind of points reads as, the same words as the web's.
enum PointsWords {
    static func kind(_ kind: String, revocation: Bool) -> String {
        let name = names[kind] ?? "Points"
        return revocation ? "Taken back: \(name.lowercased())" : name
    }

    private static let names: [String: String] = [
        "episode": "Episode",
        "movie_finished": "Film finished",
        "book_finished": "Book finished",
        "album_finished": "Album finished",
        "season_bonus": "Season complete",
        "scrobble_bonus": "Played along",
        "book_progress": "Reading",
        "listen": "Listen",
        "room_attended": "Watch party",
        "friend_added": "New friend",
        "import_first": "Moved in",
        "streak_milestone": "Streak milestone",
    ]
}
