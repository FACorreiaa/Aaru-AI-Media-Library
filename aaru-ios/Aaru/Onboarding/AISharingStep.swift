import SwiftUI

/// Let Aaru use AI with your data? (PRV-002): the first run asks before anything goes to Aaru's
/// AI provider. Allow and Don't allow each save the answer and go on; a failed save stays here
/// with the reason. Skip ends the flow as on every screen and leaves the answer unset, which is
/// not allowed.
struct AISharingStep: View {
    let model: AISharingModel
    let onBack: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void

    var body: some View {
        OnboardingPage(
            title: AISharingCopy.title,
            subtitle: AISharingCopy.lead,
            onBack: onBack,
            onSkip: onSkip,
            isBusy: model.isSaving
        ) {
            AISharingDetails()
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 20)
        } footer: {
            AISharingChoices(model: model, onSaved: { _ in onDone() })
        }
    }
}
