import SwiftUI

/// One event (SPT-002, SPT-005), as a sheet: the teams and their badges (or a card's poster),
/// the score or kick-off, the status, venue and round, then "Where to watch": the channels in
/// the chosen country first, a way to choose one when none is set, and every other country
/// folded away. Refreshes every 90 seconds while it is live and the app is active.
struct SportEventDetailView: View {
    let model: SportsModel
    let id: String

    @State private var detail: SportEventDetail?
    @State private var failed = false
    @State private var settings: SportSettingsModel?
    @State private var choosesCountry = false
    @State private var shares = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            EventHeader(event: detail.event)
                            EventFacts(event: detail.event)
                            WhereToWatch(detail: detail) { choosesCountry = true }
                            SportsCredit()
                        }
                        .frame(maxWidth: 640, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                    }
                } else if failed {
                    LoadFailedView(title: "Couldn't load this event", message: "Try again in a moment.") {
                        await load()
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(.paper))
            .navigationTitle(detail?.event.league ?? "Event")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    if detail != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Share", systemImage: "square.and.arrow.up") { shares = true }
                        }
                    }
                }
                // A share link opened while this sheet is up: give way to the share sheet.
                .onOpenURL { url in
                    if SharedLink(url) != nil {
                        dismiss()
                    }
                }
                .sheet(isPresented: $shares) {
                    ShareComposerSheet(api: model.api, target: .sportEvent(id: id), name: detail?.event.name ?? "Match")
                }
                .task(id: scenePhase == .active) {
                    guard scenePhase == .active else { return }
                    await keepFresh()
                }
                .sheet(isPresented: $choosesCountry) {
                    if let settings {
                        SportCountryPicker(model: settings) {
                            Task { await load() }
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    /// Fetches, then again every 90 seconds while the event is live.
    private func keepFresh() async {
        while !Task.isCancelled {
            await load()
            guard detail?.event.isLiveOrDue() == true else { return }
            do {
                try await Task.sleep(for: SportsRefresh.liveDelay)
            } catch {
                return
            }
        }
    }

    private func load() async {
        if let fresh = await model.event(id) {
            detail = fresh
            failed = false
        } else if detail == nil, !Task.isCancelled {
            failed = true
        }
        if settings == nil {
            let settings = model.makeSettings()
            await settings.load()
            self.settings = settings
        }
    }
}

/// The score line, large: home and away with badges either side of the score or the kick-off,
/// or a card's poster and name.
struct EventHeader: View {
    let event: SportEvent

    var body: some View {
        VStack(spacing: 16) {
            if event.isCard {
                if let url = event.imageUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Color(.stone).aspectRatio(16 / 9, contentMode: .fit)
                        }
                    }
                    .frame(maxHeight: 240)
                    .clipShape(.rect(cornerRadius: AaruRadius.panel, style: .continuous))
                    .accessibilityHidden(true)
                }
                Text(event.name)
                    .font(.aaruDisplay(.title2, weight: .semibold))
                    .foregroundStyle(Color(.ink))
                    .multilineTextAlignment(.center)
                status
            } else {
                HStack(alignment: .top, spacing: 12) {
                    TeamColumn(side: event.home)
                    VStack(spacing: 6) {
                        Text(event.scoreText ?? SportLabels.status(.scheduled, progress: nil, startsAt: event.startsAt))
                            .font(.aaruDisplay(.largeTitle, weight: .bold))
                            .foregroundStyle(Color(.ink))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        status
                    }
                    .frame(minWidth: 96)
                    .padding(.top, 12)
                    TeamColumn(side: event.away)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .card()
        .overlay(alignment: .top) {
            if event.isFavorite {
                Capsule()
                    .fill(Color(.gold))
                    .frame(width: 48, height: 3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.spoken)
    }

    @ViewBuilder private var status: some View {
        if event.status == .live {
            HStack(spacing: 6) {
                LiveDot()
                Text("Live · \(SportLabels.clock(event.progress))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.accent))
            }
        } else if event.status == .scheduled {
            Text(SportLabels.dayLabel(event.startsAt, day: event.day))
                .font(.subheadline)
                .foregroundStyle(Color(.muted))
        } else {
            Text(event.statusText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.muted))
        }
    }
}

private struct TeamColumn: View {
    let side: SportSide?

    var body: some View {
        VStack(spacing: 8) {
            SportBadge(url: side?.badgeUrl, size: 56)
            Text(side?.name ?? "TBD")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.ink))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
    }
}

/// When, where and which round.
private struct EventFacts: View {
    let event: SportEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let startsAt = event.startsAt {
                fact(
                    startsAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()),
                    systemImage: "clock"
                )
            }
            if let venue = event.venue, !venue.isEmpty {
                fact(venue, systemImage: "mappin.and.ellipse")
            }
            if let round = event.round, !round.isEmpty {
                fact(round, systemImage: "number")
            }
            if let league = event.league {
                HStack(spacing: 8) {
                    SportBadge(url: event.leagueBadgeUrl, sport: event.sport, size: 20)
                    Text(league)
                        .font(.subheadline)
                        .foregroundStyle(Color(.ink))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fact(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(Color(.ink))
    }
}

/// "Where to watch": the chosen country's channels, else a way to choose one, then the rest of
/// the world by country, folded.
private struct WhereToWatch: View {
    let detail: SportEventDetail
    let onChooseCountry: () -> Void

    @State private var showsElsewhere = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where to watch")
                .font(.aaruDisplay(.title3, weight: .semibold))
                .foregroundStyle(Color(.ink))
                .accessibilityAddTraits(.isHeader)
            if !detail.inYourCountry.isEmpty {
                if let code = detail.watchCountryCode {
                    Text(WatchCountry.name(code)).eyebrow()
                }
                channels(detail.inYourCountry)
            } else if let code = detail.watchCountryCode {
                HStack(spacing: 12) {
                    QuietNote("No channel listed in \(WatchCountry.name(code)).")
                    Spacer(minLength: 0)
                    Button("Change", action: onChooseCountry)
                        .buttonStyle(.borderless)
                }
            } else {
                QuietNote("Choose your country to see its channels first.")
                Button("Choose a country", systemImage: "globe", action: onChooseCountry)
                    .buttonStyle(.bordered)
            }
            if !detail.elsewhere.isEmpty {
                DisclosureGroup(isExpanded: $showsElsewhere) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Self.byCountry(detail.elsewhere), id: \.country) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.country).eyebrow()
                                channels(group.channels)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Other countries")
                        .font(.headline)
                        .foregroundStyle(Color(.ink))
                }
            } else if detail.inYourCountry.isEmpty {
                QuietNote("No channels are listed for this event yet.")
            }
        }
    }

    private func channels(_ broadcasts: [SportBroadcast]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(broadcasts.enumerated()), id: \.offset) { index, broadcast in
                if index > 0 {
                    Divider().padding(.leading, 52)
                }
                HStack(spacing: 12) {
                    AsyncImage(url: broadcast.logoUrl.flatMap(URL.init(string:))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Image(systemName: "tv")
                                .foregroundStyle(Color(.muted))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                    Text(broadcast.channel)
                        .font(.body)
                        .foregroundStyle(Color(.ink))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .card()
    }

    /// The other channels by country name, A to Z; channels without one last, as "Elsewhere".
    static func byCountry(_ broadcasts: [SportBroadcast]) -> [(country: String, channels: [SportBroadcast])] {
        Dictionary(grouping: broadcasts) { $0.country?.isEmpty == false ? $0.country ?? "" : "" }
            .map { (country: $0.key.isEmpty ? "Elsewhere" : $0.key, channels: $0.value, sortKey: $0.key) }
            .sorted { lhs, rhs in
                if lhs.sortKey.isEmpty != rhs.sortKey.isEmpty {
                    return !lhs.sortKey.isEmpty
                }
                return lhs.sortKey.localizedStandardCompare(rhs.sortKey) == .orderedAscending
            }
            .map { (country: $0.country, channels: $0.channels) }
    }
}
