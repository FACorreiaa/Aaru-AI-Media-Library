import SwiftUI

/// Never miss a new episode (DESIGN.md §0a, 5): a sample alert for one of the shows picked as
/// Watching, then "Turn on notifications" or "Not now". Only on a device that takes push, and only
/// when a show or anime was picked as Watching: airing alerts follow those alone.
struct NotificationsStep: View {
    let sample: OnboardingPick?
    let notifications: NotificationsModel
    let onBack: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void

    @State private var isTurningOn = false

    var body: some View {
        OnboardingPage(
            title: String(localized: "Never miss a new episode"),
            subtitle: String(localized: "Aaru tells you when a new episode of a show you're watching is out."),
            onBack: onBack,
            onSkip: onSkip,
            isBusy: isTurningOn
        ) {
            if let sample {
                SampleAlert(title: sample.hit.title)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 20)
                    .padding(.top, AaruSpace.block)
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            OnboardingProblem(message: notifications.problem) { notifications.problem = nil }
            Button("Not now", action: onDone)
                .buttonStyle(OutlineCapsuleButtonStyle())
                .disabled(isTurningOn)
            OnboardingPill(label: String(localized: "Turn on notifications"), isBusy: isTurningOn) {
                Task { await turnOn() }
            }
        }
    }

    /// Asks the system, then turns airing alerts on, as Settings → Notifications does. A refusal
    /// stays on this screen with the reason; "Not now" goes on.
    private func turnOn() async {
        isTurningOn = true
        defer { isTurningOn = false }
        await notifications.set(\.airing, true)
        if notifications.problem == nil, notifications.settings.airing {
            onDone()
        }
    }
}

/// What an airing alert looks like on the lock screen: the owl's mark, the show, "now".
private struct SampleAlert: View {
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: AaruSpace.medium) {
            OwlHead(size: 38)
                .clipShape(.rect(cornerRadius: AaruRadius.row, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: AaruSpace.small)
                    Text("now")
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                }
                Text("A new episode is out")
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
            }
        }
        .padding(AaruSpace.large)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sample alert: \(title), a new episode is out")
    }
}
