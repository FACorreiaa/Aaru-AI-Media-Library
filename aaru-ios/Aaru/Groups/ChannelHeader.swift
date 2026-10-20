import SwiftUI

/// The topic, "Reconnecting…" once the socket has been down five seconds, and the
/// "Not end-to-end" chip, which never hides.
struct ChannelHeader: View {
    let topic: String?
    /// Nil while the socket is open.
    let disconnectedSince: Date?
    @State private var explains = false

    static let reconnectingAfter: TimeInterval = 5

    var body: some View {
        HStack(spacing: 12) {
            if let topic {
                Text(topic)
                    .font(.callout)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
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
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(.muted))
            .popover(isPresented: $explains) {
                Text("""
                Group messages are stored on Aaru's server in a form it can read, so the group works \
                on all your devices. Only members of this group can see them.
                """)
                .font(.callout)
                .padding()
                .frame(idealWidth: 300)
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.paper))
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
    }
}
