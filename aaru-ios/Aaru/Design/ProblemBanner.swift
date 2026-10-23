import SwiftUI

/// The bottom message for a write or a refresh that failed. Tap to dismiss. Shared by every
/// screen; a first load that failed shows `LoadFailedView` instead.
struct ProblemBanner: View {
    let message: String?
    let onDismiss: () -> Void

    var body: some View {
        if let message {
            Button(action: onDismiss) {
                Label(message, systemImage: "exclamationmark.arrow.circlepath")
                    .font(.callout)
                    .foregroundStyle(Color(.paper))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(Color(.danger), in: .rect(cornerRadius: AaruRadius.panel, style: .continuous))
                    .contentShape(.rect(cornerRadius: AaruRadius.panel, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityHint("Dismisses this message")
            .transition(.opacity)
        }
    }
}
