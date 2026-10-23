import SwiftUI

/// The topic, "Reconnecting…" once the socket has been down five seconds, and the
/// "Not end-to-end" chip, which never hides. Every channel kind shows it, the shared list too
/// (UX-076).
struct ChannelHeader: View {
    let topic: String?
    /// Nil while the socket is open.
    let disconnectedSince: Date?
    /// `@aaru` answers in this group, so the popover says what it reads.
    var agent = false
    @State private var explains = false

    static let reconnectingAfter: TimeInterval = 5

    var body: some View {
        HStack(spacing: 12) {
            if let topic {
                Text(topic)
                    .font(.callout)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let disconnectedSince {
                TimelineView(.periodic(from: disconnectedSince, by: 1)) { context in
                    if context.date.timeIntervalSince(disconnectedSince) >= Self.reconnectingAfter {
                        Label("Reconnecting…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(Color(.muted))
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            Button {
                explains = true
            } label: {
                Label("Not end-to-end", systemImage: "lock.open")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.muted).opacity(0.12), in: .capsule)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(.muted))
            .accessibilityHint("Explains who can read group messages")
            .popover(isPresented: $explains) {
                Text(explanation)
                    .font(.callout)
                    .padding()
                    .frame(idealWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.paper))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(.line)).frame(height: 0.5) }
    }

    private var explanation: String {
        let stored = """
        Group messages are stored on Aaru's server in a form it can read, so the group works on all \
        your devices. Only members of this group can see them.
        """
        guard agent else { return stored }
        return stored + " When someone tags @aaru, it reads this channel's recent group messages to answer."
    }
}
