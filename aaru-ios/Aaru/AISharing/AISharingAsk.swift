import SwiftUI

/// PRV-002: an account that finished its first run before Aaru asked about AI sharing is asked
/// once, as the app opens. It covers the window as the first run does, offers Allow and Don't
/// allow only, and goes once the answer is saved; a failed save says so and stays.
struct AISharingAskScreen: View {
    let model: AISharingModel

    var body: some View {
        ScrollView {
            AISharingDisclosure {}
                .frame(maxWidth: 520)
                .padding(.horizontal, 20)
                .padding(.top, AaruSpace.xxlarge)
                .padding(.bottom, AaruSpace.xxlarge)
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AISharingChoices(model: model)
                .frame(maxWidth: 520)
                .padding(.horizontal, 20)
                .padding(.top, AaruSpace.medium)
                .padding(.bottom, AaruSpace.small)
                .frame(maxWidth: .infinity)
                .background(Color(.paper))
        }
        .background(Color(.paper).ignoresSafeArea())
        #if os(macOS)
            .frame(minWidth: 760, minHeight: 520)
        #endif
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier(AISharingAskID.onOpen)
    }
}

/// Identifiers a UI test waits on, so an account that has not allowed cannot hang it silently.
enum AISharingAskID {
    static let onOpen = "ai-sharing-ask"
    static let inPlace = "ai-sharing-in-place-ask"
}

/// The in-place ask (PRV-002): an AI surface used without a yes shows the disclosure with Allow
/// and Not now instead of an error. Scrolls inside whatever holds it: a sheet, or the owl's card.
struct AISharingInPlaceAsk: View {
    let model: AISharingModel
    /// Allowed, and the server has it: what was held back goes on.
    let onAllowed: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ScrollView {
            AISharingDisclosure {
                AISharingChoices(
                    model: model, decline: .notNow,
                    onSaved: { _ in onAllowed() }, onNotNow: onNotNow
                )
            }
            .padding(AaruSpace.large)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AISharingAskID.inPlace)
    }
}

/// Where the owl's composer would be, under an old chat read with AI sharing off (PRV-002): says
/// why there is nothing to type in, and opens the ask.
struct AISharingOffBar: View {
    let onReview: () -> Void

    var body: some View {
        HStack(spacing: AaruSpace.medium) {
            Text("AI data sharing is off, so Aaru can't answer.")
                .font(.callout)
                .foregroundStyle(Color(.muted))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Review", action: onReview)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, AaruSpace.large)
        .padding(.vertical, AaruSpace.small)
    }
}

extension View {
    /// The in-place ask as a sheet, for capture and the group composer. `onAllowed` runs once the
    /// sheet has been told to go, so what was held back is sent; Not now only closes it.
    func aiSharingAsk(
        isPresented: Binding<Bool>, model: AISharingModel?, onAllowed: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            if let model {
                AISharingInPlaceAsk(
                    model: model,
                    onAllowed: {
                        isPresented.wrappedValue = false
                        onAllowed()
                    },
                    onNotNow: { isPresented.wrappedValue = false }
                )
                .background(Color(.paper).ignoresSafeArea())
                #if os(macOS)
                    .frame(width: 480, height: 600)
                #endif
            }
        }
    }
}
