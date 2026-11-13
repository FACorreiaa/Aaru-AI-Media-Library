import SwiftUI

/// What Aaru says before anything goes to its AI provider (PRV-002): one wording, wherever it is
/// asked. `docs/privacy.md` holds the claims; the web says the same words.
enum AISharingCopy {
    static var title: String {
        String(localized: "Let Aaru use AI with your data?")
    }

    static var lead: String {
        String(localized: """
        The owl, capture and @aaru in groups are answered by an AI model from Anthropic. \
        If you allow it, Aaru sends Anthropic:
        """)
    }

    static var bullets: [String] {
        [
            String(localized: """
            What you ask Aaru, typed or spoken, with the screen you are on and your time zone, \
            and the files, pictures and long pastes you attach.
            """),
            String(localized: "Text and pictures you send to capture."),
            String(localized: """
            What Aaru reads from your account to answer: titles in your library with their status, \
            progress and rating, your lists, stats, favorites, listens and followed sports.
            """),
            String(localized: "In a group, your messages among a channel's last 30 when someone tags @aaru."),
        ]
    }

    static var footer: String {
        String(localized: """
        Anthropic uses it to write Aaru's answer and does not train on it. Aaru does not sell it \
        or use it for ads. If you don't allow it, these features stay off and the rest of Aaru \
        works the same. You can change this in Settings.
        """)
    }

    static var privacyPolicy: URL {
        URL(string: "https://aaruapp.com/privacy") ?? .applicationDirectory
    }
}

/// The disclosure under its heading: what is sent, what happens to it, and the privacy policy.
/// The first run shows it under its own page heading; everywhere else `AISharingDisclosure` does.
struct AISharingDetails: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.large) {
            VStack(alignment: .leading, spacing: AaruSpace.medium) {
                ForEach(AISharingCopy.bullets, id: \.self) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: AaruSpace.small) {
                        Text(verbatim: "•")
                            .foregroundStyle(Color(.muted))
                            .accessibilityHidden(true)
                        Text(bullet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(Color(.ink))
            Text(AISharingCopy.footer)
                .font(.footnote)
                .foregroundStyle(Color(.muted))
                .fixedSize(horizontal: false, vertical: true)
            Link("Privacy policy", destination: AISharingCopy.privacyPolicy)
                .font(.footnote.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// AI sharing's one disclosure (PRV-002): the question, what Aaru sends and to whom, and the
/// caller's actions under it. The full-screen ask, the in-place ask and Settings all show this.
struct AISharingDisclosure<Actions: View>: View {
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.large) {
            VStack(alignment: .leading, spacing: AaruSpace.small) {
                Text(AISharingCopy.title)
                    .font(.aaruDisplay(.title2, weight: .bold))
                    .foregroundStyle(Color(.ink))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(AISharingCopy.lead)
                    .font(.body)
                    .foregroundStyle(Color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            AISharingDetails()
            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The two answers, the same size and one above the other: neither is the quiet one. "Don't
/// allow" saves a no; "Not now" (the in-place ask) saves nothing and leaves the answer as it was.
struct AISharingChoices: View {
    enum Decline {
        case dontAllow, notNow
    }

    let model: AISharingModel
    var decline = Decline.dontAllow
    /// The answer reached the server.
    var onSaved: (_ allowed: Bool) -> Void = { _ in }
    /// "Not now" was tapped.
    var onNotNow: () -> Void = {}

    /// The answer on its way, so its own button shows the wait.
    @State private var sending: Bool?

    var body: some View {
        VStack(spacing: AaruSpace.medium) {
            OnboardingProblem(message: model.problem) { model.problem = nil }
            Button {
                switch decline {
                case .dontAllow: answer(false)
                case .notNow: onNotNow()
                }
            } label: {
                if sending == false {
                    ProgressView()
                } else {
                    Text(decline == .dontAllow ? String(localized: "Don't allow") : String(localized: "Not now"))
                }
            }
            .buttonStyle(OutlineCapsuleButtonStyle())
            .disabled(sending != nil)
            .accessibilityIdentifier("ai-sharing-decline")
            OnboardingPill(label: String(localized: "Allow"), isBusy: sending == true) { answer(true) }
                .disabled(sending != nil)
                .accessibilityIdentifier("ai-sharing-allow")
        }
    }

    private func answer(_ allowed: Bool) {
        guard sending == nil else { return }
        sending = allowed
        Task {
            let saved = await model.set(allowed)
            sending = nil
            if saved {
                onSaved(allowed)
            }
        }
    }
}
