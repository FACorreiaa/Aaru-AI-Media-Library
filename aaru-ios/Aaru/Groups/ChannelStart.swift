import SwiftUI

/// The top of a channel's timeline: where it began, "Load earlier", a spinner while the first
/// page loads, or the first-load error with Try again (UX-063).
struct ChannelStart: View {
    let channel: GroupChannel
    let model: ChannelModel

    var body: some View {
        if model.reachedStart {
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(channel.name)").font(.aaruDisplay(.title2, weight: .semibold))
                Text(channel.isDefault ? "The start of the group." : "The start of #\(channel.name).")
                    .foregroundStyle(Color(.muted))
            }
            .padding(16)
            .accessibilityElement(children: .combine)
        } else if model.hasLoaded {
            Button(model.loadingOlder ? "Loading…" : "Load earlier") {
                Task { await model.loadOlder() }
            }
            .buttonStyle(.borderless)
            .disabled(model.loadingOlder)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
        } else if let problem = model.loadProblem {
            LoadFailedView(title: "Couldn't open #\(channel.name)", message: problem) {
                await model.loadLatest()
            }
            .padding(.top, 40)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(24)
        }
    }
}
