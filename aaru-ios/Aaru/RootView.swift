import AaruCore
import SwiftUI

/// Placeholder root until APP-001 builds the real shell.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Aaru")
                .font(.largeTitle.weight(.semibold))
            Text(MediaType.allCases.map(\.rawValue).joined(separator: " · "))
                .foregroundStyle(.secondary)
            LabeledContent("Channel", value: AppEnvironment.channel)
            LabeledContent("API", value: AppEnvironment.apiBaseURL?.absoluteString ?? "not set")
        }
        .padding()
        .frame(maxWidth: 420)
    }
}

#Preview {
    RootView()
}
