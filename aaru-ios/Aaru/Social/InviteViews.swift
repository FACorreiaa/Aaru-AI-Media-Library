import AaruAPI
import SwiftUI

// Friends' invite rows and the just-made link (SOC-002), out of `FriendsView.swift`.

extension FriendInvite: @retroactive Identifiable {
    public var id: String {
        code
    }
}

extension FriendInvite {
    var plea: String {
        guard let title else { return "Join me on Aaru." }
        return InviteWords.plea(title.title, kind: MediaKind(type: title._type, isAnime: title.isAnime))
    }
}

/// One open invite: what it says and how long it has left, with the share sheet a tap away.
struct InviteRow: View {
    let invite: FriendInvite

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invite.plea).lineLimit(2)
                Text(InviteWords.expiry(invite.expiresAt))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            Spacer(minLength: 8)
            if let url = URL(string: invite.url) {
                ShareLink(item: url, message: Text(invite.plea)) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Share invite")
            }
        }
    }
}

/// The link just made: what it will say, and the share sheet to send it.
struct FreshInviteSheet: View {
    let invite: FriendInvite
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let title = invite.title {
                    PosterView(
                        url: title.posterUrl.flatMap(URL.init(string:)),
                        kind: MediaKind(type: title._type, isAnime: title.isAnime)
                    )
                    .frame(width: 96)
                } else {
                    Image(systemName: "envelope.open")
                        .font(.largeTitle.weight(.light))
                        .imageScale(.large)
                        .foregroundStyle(Color(.accent))
                }
                VStack(spacing: 8) {
                    Text("Your invite is ready")
                        .font(.aaruDisplay(.title))
                    Text("“\(invite.plea)”")
                        .font(.aaruDisplay(.body, weight: .regular, italic: true))
                    Text("It works once, for the first person who opens it, for two weeks.")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .multilineTextAlignment(.center)
                }
                if let url = URL(string: invite.url) {
                    ShareLink(item: url, message: Text(invite.plea)) {
                        Label("Send invite", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
