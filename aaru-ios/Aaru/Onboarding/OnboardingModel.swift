import AaruAPI
import AaruCore
import Foundation
import Observation

typealias OnboardingKind = Onboarding.Kind
typealias OnboardingStep = Onboarding.Step
typealias OnboardingRelatedItem = Components.Schemas.OnboardingRelatedItem

/// One poster picked in the first run. `saved` once the server has it: it is then in the library,
/// is not sent again, and keeps the status it was saved with.
struct OnboardingPick: Identifiable, Hashable {
    let hit: CatalogHit
    let kind: OnboardingKind
    var status: LibraryStatus
    var saved: Saved?

    struct Saved: Hashable {
        let titleID: String
        let libraryItemID: String
    }

    var id: String {
        hit.id
    }
}

/// One kind's rows for its picker step, as `GET /v1/onboarding/rows` sent them.
enum OnboardingRows {
    case loading
    case loaded([DiscoverRow])
    case failed(String)
}

/// ONB-001: a new account's first run (DESIGN.md §0a). Holds what the user chose across the
/// steps; the step list itself is `Onboarding.steps` in AaruCore, the same cases as the web.
@MainActor
@Observable
final class OnboardingModel {
    /// The kinds chosen on the first screen.
    var kinds: Set<OnboardingKind> = []
    /// Every pick, in the order it was first tapped. Unsaved picks of a kind no longer chosen are
    /// left out of what the flow counts (`livePicks`).
    private(set) var picks: [OnboardingPick] = []
    private(set) var rows: [OnboardingKind: OnboardingRows] = [:]
    /// Nil until the related call has answered.
    private(set) var related: [OnboardingRelatedItem]?
    /// Related titles tapped to add as planned, by `CatalogHit.id`.
    var relatedChosen: [String] = []
    private(set) var isSaving = false
    /// Waiting for the related answer before the next screen.
    private(set) var isAwaitingRelated = false
    /// A save or a wait is running: the pill spins and Skip waits.
    var isBusy: Bool {
        isSaving || isAwaitingRelated
    }

    /// The last save did not reach the server: the pill reads "Try again".
    private(set) var saveFailed = false
    /// A failed save, shown on the step it happened on; what was picked stays.
    var problem: String?

    /// The most one picks call takes; the server answers 422 past it.
    static let batchLimit = 60
    /// The most titles the related call takes.
    static let relatedLimit = 30

    @ObservationIgnored let api: Client?
    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private var relatedTask: Task<Void, Never>?
    /// Picks the catalog could not resolve: a second Continue goes on without them.
    @ObservationIgnored private var missed: Set<String> = []

    init(api: Client?, library: LibraryModel) {
        self.api = api
        self.library = library
    }

    /// A new screen starts clean: no message, no "Try again" from the last one.
    func clearProblem() {
        problem = nil
        saveFailed = false
    }

    // MARK: Steps

    /// Whether this device can take airing alerts: iPhone and iPad register for push; the Mac
    /// does not, so its flow leaves the alerts screen out.
    static var pushSupported: Bool {
        #if os(iOS)
            PushRegistrar.current != nil
        #else
            false
        #endif
    }

    /// Picks the flow counts: every saved one, and unsaved ones of a kind still chosen.
    var livePicks: [OnboardingPick] {
        picks.filter { $0.saved != nil || kinds.contains($0.kind) }
    }

    var steps: [OnboardingStep] {
        Onboarding.steps(
            kinds: kinds,
            picks: livePicks.map { Onboarding.Pick(kind: $0.kind, status: Onboarding.coreStatus($0.status)) },
            hasRelated: related?.isEmpty == false,
            pushSupported: Self.pushSupported
        )
    }

    func step(after current: OnboardingStep) -> OnboardingStep? {
        let list = steps
        guard let index = list.firstIndex(of: current) else { return nil }
        return list.indices.contains(index + 1) ? list[index + 1] : nil
    }

    func step(before current: OnboardingStep) -> OnboardingStep? {
        let list = steps
        guard let index = list.firstIndex(of: current), index > 0 else { return nil }
        return list[index - 1]
    }

    // MARK: Picks

    func pick(for hit: CatalogHit) -> OnboardingPick? {
        picks.first { $0.id == hit.id }
    }

    /// The picks of one kind, in tap order.
    func picks(of kind: OnboardingKind) -> [OnboardingPick] {
        picks.filter { $0.kind == kind }
    }

    /// The picks of one kind not saved yet: what Continue sends.
    func unsent(_ kind: OnboardingKind) -> [OnboardingPick] {
        picks.filter { $0.kind == kind && $0.saved == nil }
    }

    /// The title's library item when the user has it already (a row marks it, or the library
    /// has it): such a poster is shown as added and never sent.
    func libraryItemID(_ hit: CatalogHit) -> String? {
        hit.libraryItemId ?? library.entry(matching: hit)?.id
    }

    /// One tap on a poster: its status moves on through the kind's cycle.
    func cycle(_ hit: CatalogHit, kind: OnboardingKind) {
        let current = pick(for: hit)?.status
        set(
            hit,
            kind: kind,
            status: Onboarding.nextStatus(current.map(Onboarding.coreStatus), kind: kind)
                .map(Onboarding.apiStatus)
        )
    }

    /// Sets one poster's status, nil taking it off. A saved pick, or a title already in the
    /// library, stays as it is. New picks join the end. Past a full batch a new pick is refused.
    func set(_ hit: CatalogHit, kind: OnboardingKind, status: LibraryStatus?) {
        guard libraryItemID(hit) == nil else { return }
        let index = picks.firstIndex { $0.id == hit.id }
        if let index, picks[index].saved != nil {
            return
        }
        problem = nil
        switch (index, status) {
        case let (index?, nil): picks.remove(at: index)
        case let (index?, status?): picks[index].status = status
        case let (nil, status?):
            guard unsent(kind).count < Self.batchLimit else {
                problem = "\(Self.batchLimit) is the most one screen saves. Continue, then add more from Search."
                return
            }
            picks.append(OnboardingPick(hit: hit, kind: kind, status: status))
        case (nil, nil): return
        }
    }

    // MARK: Rows

    /// Loads one kind's rows once; a failure can be retried.
    func loadRows(_ kind: OnboardingKind, force: Bool = false) async {
        if !force, let current = rows[kind], !current.failed {
            return
        }
        guard let api else {
            rows[kind] = .loaded([])
            return
        }
        rows[kind] = .loading
        do {
            switch try await api.getOnboardingRows(query: .init(kind: kind.rowKind)) {
            case let .ok(response):
                rows[kind] = try .loaded(response.body.json.rows.filter { !$0.items.isEmpty })
            case let .default(_, error):
                rows[kind] = .failed((try? error.body.json.message) ?? "The titles didn't load.")
            }
        } catch is CancellationError {
            rows[kind] = nil
        } catch {
            rows[kind] = .failed("Aaru could not reach the server.")
        }
    }

    // MARK: Saving

    /// Sends one kind's unsaved picks as one call (one journaled action). True when there was
    /// nothing to send or it was saved; on failure the picks stay and `problem` says why.
    func save(_ kind: OnboardingKind) async -> Bool {
        let batch = unsent(kind)
        guard !batch.isEmpty else { return true }
        // Continue again with only titles the catalog could not find: go on without them.
        if batch.allSatisfy({ missed.contains($0.id) }) {
            picks.removeAll { pick in batch.contains { $0.id == pick.id } }
            problem = nil
            return true
        }
        guard let missedCount = await send(batch) else { return false }
        startRelated()
        return missedCount == 0
    }

    /// The related titles tapped, added as planned in one call.
    func saveRelated() async -> Bool {
        let chosen = relatedChosen.compactMap { id in related?.first { $0.hit.id == id } }
        let batch = chosen.compactMap { item -> OnboardingPick? in
            guard libraryItemID(item.hit) == nil, pick(for: item.hit)?.saved == nil else { return nil }
            let kind = OnboardingKind(MediaKind(type: item.hit._type, isAnime: item.hit.isAnime))
            return OnboardingPick(hit: item.hit, kind: kind, status: .wishlist)
        }
        guard !batch.isEmpty else { return true }
        // A related title the catalog could not resolve is simply not added: nothing to retry.
        guard await send(batch, appending: true) != nil else { return false }
        problem = nil
        return true
    }

    /// One `POST /v1/onboarding/picks`. The answer's `index` is the position in `batch`; a ref
    /// that resolved to no title stays unsaved, so it can be tried again or taken off. The count of
    /// those, or nil when the call failed.
    private func send(_ batch: [OnboardingPick], appending: Bool = false) async -> Int? {
        guard let api else { return nil }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        let items = batch.map { Components.Schemas.AddLibraryItem(mediaRef: $0.hit.mediaRef, status: $0.status) }
        do {
            switch try await api.addOnboardingPicks(body: .json(.init(items: items))) {
            case let .ok(response):
                let answer = try response.body.json
                saveFailed = false
                if appending {
                    picks += batch
                }
                for item in answer.items where batch.indices.contains(item.index) {
                    let id = batch[item.index].id
                    if let index = picks.firstIndex(where: { $0.id == id }) {
                        picks[index].saved = .init(titleID: item.titleId, libraryItemID: item.libraryItemId)
                    }
                }
                if appending {
                    picks.removeAll { pick in pick.saved == nil && batch.contains { $0.id == pick.id } }
                }
                if answer.missed > 0 {
                    let found = Set(answer.items.map(\.index))
                    for (index, pick) in batch.enumerated() where !found.contains(index) {
                        missed.insert(pick.id)
                    }
                    problem = answer.missed == 1
                        ? "One title couldn't be found in the catalog. Continue to go on without it."
                        : "\(answer.missed) titles couldn't be found in the catalog. Continue to go on without them."
                }
                // The new items reach Home, Library and Up Next the way other bulk writes do.
                Task { [library, api] in await library.sync(api: api) }
                return answer.missed
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Your picks weren't saved."
            }
        } catch {
            problem = "Your picks weren't saved. Aaru could not reach the server."
        }
        saveFailed = true
        return nil
    }

    // MARK: Related

    /// Asks for the saved picks' relations in the background, replacing any earlier ask, so the
    /// answer is usually there by the time the flow reaches it.
    private func startRelated() {
        var ids: [String] = []
        for pick in picks {
            if let titleID = pick.saved?.titleID, !ids.contains(titleID) {
                ids.append(titleID)
            }
        }
        ids = Array(ids.prefix(Self.relatedLimit))
        guard let api, !ids.isEmpty else { return }
        relatedTask?.cancel()
        relatedTask = Task { [weak self] in
            let items: [OnboardingRelatedItem]? = switch try? await api.getOnboardingRelated(
                body: .json(.init(titleIds: ids))
            ) {
            case let .ok(response): try? response.body.json.items
            default: []
            }
            guard !Task.isCancelled, let self else { return }
            // A title saved since (or already in the library) is not offered again.
            related = (items ?? []).filter { self.libraryItemID($0.hit) == nil && self.pick(for: $0.hit) == nil }
        }
    }

    /// Waits for the related answer, if one was asked for.
    func awaitRelated() async {
        guard let relatedTask else { return }
        isAwaitingRelated = true
        defer { isAwaitingRelated = false }
        await relatedTask.value
    }

    /// The related titles under the pick they come from, in the server's order: "More from Dune".
    var relatedGroups: [RelatedGroup] {
        var groups: [RelatedGroup] = []
        for item in related ?? [] {
            if let index = groups.firstIndex(where: { $0.id == item.fromTitleId }) {
                groups[index].hits.append(item.hit)
            } else {
                groups.append(RelatedGroup(id: item.fromTitleId, fromTitle: item.fromTitle, hits: [item.hit]))
            }
        }
        return groups
    }

    struct RelatedGroup: Identifiable {
        let id: String
        let fromTitle: String
        var hits: [CatalogHit]
    }

    func toggleRelated(_ hit: CatalogHit) {
        if let index = relatedChosen.firstIndex(of: hit.id) {
            relatedChosen.remove(at: index)
        } else {
            relatedChosen.append(hit.id)
        }
    }

    // MARK: Finishing

    /// `PUT /v1/me/onboarding`, sent without waiting: leaving is never held up by it. A failure
    /// leaves the flow pending on the server, so it shows again on the next launch, with what was
    /// saved still saved.
    func finish(skipped: Bool) {
        relatedTask?.cancel()
        guard let api else { return }
        Task { _ = try? await api.finishOnboarding(body: .json(.init(skipped: skipped))) }
    }

    /// A show or anime saved as Watching: the sample on the alerts screen.
    var sampleAiring: OnboardingPick? {
        livePicks.first { $0.kind.airs && $0.status == .inProgress }
    }
}

private extension OnboardingRows {
    var failed: Bool {
        if case .failed = self {
            true
        } else {
            false
        }
    }
}
