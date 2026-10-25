import Foundation
import Observation

/// Decides when to ask for an App Store rating.
///
/// A success is a tick, a page or a title finished in the app, counted at most once per calendar
/// day, so the ask comes after progress on three different days. A milestone (the first title
/// finished, a badge earned live) asks at once, even on day one. Nothing asks more than once in
/// 120 days or after the user turned it off in Settings, and successes wait out the first 24
/// hours. The system still decides whether its sheet shows; `ReviewPromptPresenter` makes the
/// request.
///
/// Logic only, kept per device in `defaults` (nothing leaves the device, `docs/privacy.md`), with
/// the clock injected so the rules hold without waiting days.
@MainActor
@Observable
final class ReviewPrompter {
    static let shared = ReviewPrompter()

    static let successesBeforePrompt = 3
    static let firstSessionGrace: TimeInterval = 24 * 60 * 60
    static let cooldown: TimeInterval = 120 * 24 * 60 * 60

    /// Settings → About → "Ask me to rate Aaru". On by default.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                skipPrompt()
            }
        }
    }

    /// Set when a success or a milestone makes a prompt due; the presenter clears it.
    private(set) var isPromptDue = false

    /// A milestone waiting for the presenter: it skips the count and the first-day grace.
    @ObservationIgnored private var milestoneDue = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    private static let enabledKey = "review.enabled"
    private static let firstSeenKey = "review.firstSeenAt"
    private static let successCountKey = "review.successCount"
    private static let lastCountedDayKey = "review.lastCountedDay"
    private static let lastPromptKey = "review.lastPromptAt"
    private static let milestonePrefix = "review.milestone."

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        if defaults.object(forKey: Self.firstSeenKey) == nil {
            defaults.set(now(), forKey: Self.firstSeenKey)
        }
    }

    var successCount: Int {
        defaults.integer(forKey: Self.successCountKey)
    }

    /// Progress the user made in the app. Counts once per calendar day.
    func recordSuccess() {
        let today = calendar.startOfDay(for: now())
        let lastCounted = defaults.object(forKey: Self.lastCountedDayKey) as? Date
        if lastCounted.map({ !calendar.isDate($0, inSameDayAs: today) }) ?? true {
            defaults.set(today, forKey: Self.lastCountedDayKey)
            defaults.set(successCount + 1, forKey: Self.successCountKey)
        }
        isPromptDue = shouldPrompt
    }

    /// A first-time or celebratory moment: asks without waiting for the count or the first day.
    /// Cooldown and the Settings switch still apply. With `once`, it fires at most one time per
    /// install; the key is spent on the first call, asked or not, because the moment has passed.
    func recordMilestone(once key: String? = nil) {
        if let key {
            let seenKey = Self.milestonePrefix + key
            guard !defaults.bool(forKey: seenKey) else { return }
            defaults.set(true, forKey: seenKey)
        }
        guard isEnabled, !isCoolingDown else { return }
        milestoneDue = true
        isPromptDue = true
    }

    /// Whether to ask now: the presenter's last check before it does.
    var shouldPrompt: Bool {
        guard isEnabled, !isCoolingDown else { return false }
        if milestoneDue {
            return true
        }
        guard successCount >= Self.successesBeforePrompt else { return false }
        if let firstSeen = defaults.object(forKey: Self.firstSeenKey) as? Date,
           now().timeIntervalSince(firstSeen) < Self.firstSessionGrace
        {
            return false
        }
        return true
    }

    /// The review was requested: start counting again from zero.
    func didPrompt() {
        defaults.set(0, forKey: Self.successCountKey)
        defaults.set(now(), forKey: Self.lastPromptKey)
        milestoneDue = false
        isPromptDue = false
    }

    /// The moment passed (the window closed, the app went to the background): wait for the next
    /// success or milestone.
    func skipPrompt() {
        milestoneDue = false
        isPromptDue = false
    }

    private var isCoolingDown: Bool {
        guard let lastPrompt = defaults.object(forKey: Self.lastPromptKey) as? Date else { return false }
        return now().timeIntervalSince(lastPrompt) < Self.cooldown
    }
}
