import SwiftUI

/// The heron at rest (DESIGN.md "Agent presence"): the reed mark, breathing slowly while Aaru is
/// working on something for the user (a plan waiting, an import matching). Still under Reduce
/// Motion. Never shown when nothing is in progress.
struct AgentPresence: View {
    var label = "Aaru is working"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Image(.reedMark)
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .opacity(breathing ? 1 : 0.55)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                value: breathing
            )
            .onAppear { breathing = !reduceMotion }
            .accessibilityLabel(label)
    }
}
