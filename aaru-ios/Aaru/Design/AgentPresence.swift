import SwiftUI

/// Aaru at work (DESIGN.md "Brand"): the owl's head on the night disc, breathing slowly while
/// Aaru is working on something for the user (a plan waiting, an import matching). Still under
/// Reduce Motion. Never shown when nothing is in progress.
struct AgentPresence: View {
    var label = "Aaru is working"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Image(.owlMark)
            .resizable()
            .scaledToFill()
            .frame(width: 20, height: 20)
            .background(Color(.night))
            .clipShape(Circle())
            .opacity(breathing ? 1 : 0.7)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                value: breathing
            )
            .onAppear { breathing = !reduceMotion }
            .accessibilityLabel(label)
    }
}
