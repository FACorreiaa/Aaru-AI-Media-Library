import SwiftUI

// GRP-011: how `@aaru` appears in a group. Aaru is the heron on its medallion, never a monogram,
// so it never reads as a member.

/// The heron on the medallion. Breathes while Aaru is working; still under Reduce Motion.
struct AaruAvatar: View {
    var size: CGFloat = 36
    var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhale = false

    var body: some View {
        ZStack {
            Circle().fill(Color(.medallion))
            Image(.mascot)
                .resizable()
                .scaledToFit()
                .padding(.top, size * 0.08)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .scaleEffect(inhale && !reduceMotion ? 1.06 : 1)
        .onAppear {
            guard breathing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { inhale = true }
        }
        // Turning Reduce Motion on mid-breath stops it at rest.
        .onChange(of: reduceMotion) { _, reduce in
            if reduce {
                inhale = false
            }
        }
        .accessibilityHidden(true)
    }
}

/// A reply from Aaru: the heron, "Aaru" with an assistant tag, what it answers, the text, and
/// title cards whose buttons are the reader's own taps.
struct AgentMessageRow: View {
    let message: GroupMessage
    /// The mention it answers, when that message is loaded.
    let answering: GroupMessage?
    let myHandle: String?
    /// The reader's own add of a title the answer points to; nil when added, else why not.
    let onAdd: (TitleSummary) async -> String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AaruAvatar()
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Aaru").font(.subheadline.weight(.semibold))
                    Text("assistant")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color(.medallion).opacity(0.25), in: .capsule)
                    Text(message.createdAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                }
                if let answering, !answering.deleted {
                    Text("Replying to \(answering.author.map { "@\($0.handle)" } ?? "someone"): \(answering.body)")
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
                if message.deleted {
                    Text("Deleted").italic().foregroundStyle(Color(.muted))
                } else if message.veiled {
                    SpoilerReveal(message: message, myHandle: myHandle, onAdd: onAdd)
                } else {
                    AgentBody(message: message, myHandle: myHandle, onAdd: onAdd)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aaru, assistant")
    }
}

/// A veiled answer: the veil until tapped, then the answer.
private struct SpoilerReveal: View {
    let message: GroupMessage
    let myHandle: String?
    let onAdd: (TitleSummary) async -> String?
    @State private var shown = false

    var body: some View {
        if shown {
            AgentBody(message: message, myHandle: myHandle, onAdd: onAdd)
        } else {
            SpoilerVeil { shown = true }
        }
    }
}

private struct AgentBody: View {
    let message: GroupMessage
    let myHandle: String?
    let onAdd: (TitleSummary) async -> String?

    var body: some View {
        Text(MentionText.attributed(message.body, myHandle: myHandle))
            .textSelection(.enabled)
        if let components = message.components, !components.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(components, id: \.title.id) { component in
                        AgentTitleCard(title: component.title, onAdd: onAdd)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// One title Aaru pointed to. "Add to my library" is the reader's own wishlist add.
struct AgentTitleCard: View {
    let title: TitleSummary
    /// Nil when added, else why not.
    let onAdd: (TitleSummary) async -> String?
    @State private var state = AddState.idle

    enum AddState: Equatable {
        case idle, adding, added
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: title.posterURL, kind: title.mediaKind)
                .frame(width: 96)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(title.title)
            Text(title.title).font(.caption.weight(.medium)).lineLimit(3)
            if let year = title.year {
                Text(String(year)).font(.caption2).foregroundStyle(Color(.muted))
            }
            switch state {
            case .added:
                Label("Added", systemImage: "checkmark")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color(.accent))
            case .adding:
                ProgressView().controlSize(.small)
            case let .failed(problem):
                Text(problem).font(.caption2).foregroundStyle(Color(.danger)).lineLimit(2)
            case .idle:
                Button("Add to my library", systemImage: "plus") { Task { await add() } }
                    .font(.caption2.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(width: 104, alignment: .leading)
        .accessibilityElement(children: .contain)
        .contextMenu {
            if state == .idle {
                Button("Add to my library", systemImage: "plus") { Task { await add() } }
            }
        }
    }

    private func add() async {
        state = .adding
        if let problem = await onAdd(title) {
            state = .failed(problem)
        } else {
            state = .added
        }
    }
}

/// "Aaru is thinking…" while an answer is on its way.
struct AgentThinkingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            AaruAvatar(breathing: true)
            Text("Aaru is thinking…")
                .font(.subheadline)
                .foregroundStyle(Color(.muted))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Aaru in the member list, with what it can and cannot do.
struct AaruMemberRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AaruAvatar(size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aaru · answers when tagged")
                Text("""
                Tag @aaru to ask. It reads this channel's recent group messages, and your own library \
                when that helps. It can't change anything.
                """)
                .font(.caption)
                .foregroundStyle(Color(.muted))
            }
        }
    }
}
