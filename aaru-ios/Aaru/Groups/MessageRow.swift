import AaruAPI
import SwiftUI

/// One message as the channel lays it out: whether it starts a run (name and monogram), and
/// whether a day divider or the "New" line goes above it.
struct MessageLine: Identifiable {
    let message: GroupMessage
    let startsRun: Bool
    let day: Date?
    let isFirstUnread: Bool

    var id: String {
        message.id
    }

    /// A run is one author's messages within five minutes on the same day.
    static let runGap: TimeInterval = 5 * 60

    static func lines(
        _ messages: [GroupMessage], firstUnreadID: String?, calendar: Calendar = .current
    ) -> [MessageLine] {
        var lines: [MessageLine] = []
        var previous: GroupMessage?
        for message in messages {
            let newDay = previous.map { !calendar.isDate($0.createdAt, inSameDayAs: message.createdAt) } ?? true
            let isFirstUnread = message.id == firstUnreadID
            let continues = previous.map { previous in
                !previous.deleted && !message.deleted
                    && previous.author?.userId == message.author?.userId && message.author != nil
                    && message.createdAt.timeIntervalSince(previous.createdAt) < runGap
            } ?? false
            lines.append(MessageLine(
                message: message,
                startsRun: newDay || isFirstUnread || !continues,
                day: newDay ? message.createdAt : nil,
                isFirstUnread: isFirstUnread
            ))
            previous = message
        }
        return lines
    }
}

/// A flat message row: monogram and name at the start of a run, then the text.
struct MessageRow: View {
    let line: MessageLine
    let myUserID: String?
    let myHandle: String?
    @State private var revealed = false
    @State private var spoilerShown = false

    private var message: GroupMessage {
        line.message
    }

    private var mentionsMe: Bool {
        myUserID.map { message.mentions.contains($0) } ?? false
    }

    var body: some View {
        MessageScaffold(
            monogram: line.startsRun ? (message.author?.monogram ?? "?") : nil,
            name: line.startsRun ? authorName : nil,
            time: message.createdAt,
            highlighted: mentionsMe
        ) {
            content
        }
    }

    private var authorName: String {
        guard let author = message.author else { return "Deleted account" }
        return author.displayName ?? "@\(author.handle)"
    }

    @ViewBuilder
    private var content: some View {
        if message.deleted {
            Text("Message deleted").italic().foregroundStyle(Color(.muted))
        } else if message.fromBlocked, !revealed {
            HStack(spacing: 8) {
                Text("Message from someone you blocked").foregroundStyle(Color(.muted))
                Button("Show") { revealed = true }
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
        } else if message.veiled, !spoilerShown {
            SpoilerVeil { spoilerShown = true }
        } else {
            let edited = Text(message.editedAt == nil ? "" : "  (edited)")
                .font(.caption)
                .foregroundStyle(Color(.muted))
            Text("\(Text(MentionText.attributed(message.body, myHandle: myHandle)))\(edited)")
                .textSelection(.enabled)
            // Only the author is ever sent the stamp.
            if let stamp = message.spoiler?.label {
                Label(stamp, systemImage: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(Color(.muted))
                    .accessibilityLabel("Marked as a spoiler: \(stamp)")
            }
        }
    }
}

/// A message on its way: dimmed until the server confirms, with retry and discard on failure.
struct OutgoingRow: View {
    let outgoing: ChannelModel.Outgoing
    let startsRun: Bool
    let sender: SocialUser?
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        MessageScaffold(
            monogram: startsRun ? (sender?.monogram ?? "?") : nil,
            name: startsRun ? (sender.map { $0.displayName ?? "@\($0.handle)" } ?? "You") : nil,
            time: outgoing.createdAt,
            highlighted: false
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(outgoing.body).opacity(outgoing.failed ? 1 : 0.5)
                if outgoing.failed {
                    HStack(spacing: 12) {
                        Label("Not sent", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                        Button("Retry", action: onRetry)
                        Button("Discard", role: .destructive, action: onDiscard)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        }
        .accessibilityHint(outgoing.failed ? "Not sent" : "Sending")
    }
}

/// The shared row shape: a 36-point gutter for the monogram, then name, time and text.
private struct MessageScaffold<Content: View>: View {
    let monogram: String?
    let name: String?
    let time: Date
    let highlighted: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let monogram {
                Monogram(text: monogram, size: 36)
            } else {
                Color.clear.frame(width: 36, height: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let name {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(name).font(.subheadline.weight(.semibold))
                        Text(time, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(Color(.muted))
                    }
                }
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, name == nil ? 1 : 10)
        .padding(.bottom, 1)
        .background {
            if highlighted {
                HStack(spacing: 0) {
                    Color(.accent).frame(width: 2)
                    Color(.accent).opacity(0.08)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DayDivider: View {
    let day: Date

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.separator).frame(height: 1)
            Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(.muted))
                .fixedSize()
            Rectangle().fill(.separator).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The thin accent line where the user stopped reading.
struct NewDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color(.accent)).frame(height: 1)
            Text("New")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(.accent))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityLabel("New messages")
    }
}

/// A generated monogram on the medallion tint. Aaru has no avatar uploads.
struct Monogram: View {
    let text: String
    var size: CGFloat = 36

    var body: some View {
        Text(text)
            .font(size > 40 ? .headline : .subheadline.weight(.medium))
            .frame(width: size, height: size)
            .background(Color(.medallion).opacity(0.2), in: .circle)
            .accessibilityHidden(true)
    }
}

enum MentionText {
    /// The body with `@handle` tags in semibold, and tags of the reader in the accent.
    static func attributed(_ body: String, myHandle: String?) -> AttributedString {
        var text = AttributedString(body)
        let mine = myHandle.map { "@\($0)" }
        for match in body.matches(of: /@[A-Za-z0-9_]{3,20}/) {
            guard let lower = AttributedString.Index(match.range.lowerBound, within: text),
                  let upper = AttributedString.Index(match.range.upperBound, within: text)
            else { continue }
            let range = lower ..< upper
            text[range].font = .body.weight(.semibold)
            if String(match.output).lowercased() == mine {
                text[range].foregroundColor = Color(.accent)
            }
        }
        return text
    }
}
