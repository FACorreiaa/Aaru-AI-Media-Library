import SwiftUI

/// The one first-load error state (UX-063): what went wrong and "Try again". Shown in place of
/// content only when nothing has loaded yet, so a failure never reads as an empty library or an
/// empty calendar (UX-062). Later failures go to `ProblemBanner` over what is already shown.
/// The owl is there, still (an error is no place for idle life), with the no-connection mark.
struct LoadFailedView: View {
    var title = "Couldn't load this"
    let message: String
    let retry: () async -> Void

    @State private var retrying = false

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                OwlMedallion(size: 88)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(.ink))
                            .frame(width: 30, height: 30)
                            .background(Color(.surface), in: .circle)
                            .overlay(Circle().strokeBorder(Color(.line)))
                            .accessibilityHidden(true)
                    }
                    .padding(.bottom, 4)
            }
        } description: {
            Text(message)
        } actions: {
            Button {
                Task {
                    retrying = true
                    await retry()
                    retrying = false
                }
            } label: {
                if retrying {
                    ProgressView()
                } else {
                    Text("Try again")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(retrying)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LoadFailedView(message: "Aaru could not reach the server.") {}
        .background(Color(.paper))
}
