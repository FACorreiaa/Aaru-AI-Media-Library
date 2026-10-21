import SwiftUI

/// The one first-load error state (UX-063): what went wrong and "Try again". Shown in place of
/// content only when nothing has loaded yet, so a failure never reads as an empty library or an
/// empty calendar (UX-062). Later failures go to `ProblemBanner` over what is already shown.
struct LoadFailedView: View {
    var title = "Couldn't load this"
    let message: String
    let retry: () async -> Void

    @State private var retrying = false

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
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
