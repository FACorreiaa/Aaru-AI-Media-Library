import SwiftUI

/// The first screen (DESIGN.md §0a, 1): which kinds the user keeps, any number of them. Each
/// one chosen gets its own picker screen. "Bring your history instead" ends the flow on Import.
struct KindsStep: View {
    @Bindable var model: OnboardingModel
    let onSkip: () -> Void
    let onContinue: () -> Void
    let onImport: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingPage(
            title: "What do you keep?",
            subtitle: "Pick what you watch, read and listen to. You can add the rest any time.",
            onSkip: onSkip,
            showsOwl: true
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: AaruSpace.medium)],
                spacing: AaruSpace.medium
            ) {
                ForEach(OnboardingKind.allCases) { kind in
                    KindCard(kind: kind, isOn: model.kinds.contains(kind)) { toggle(kind) }
                }
            }
            .padding(.horizontal, 20)
        } footer: {
            Button("Bring your history instead", action: onImport)
                .buttonStyle(OutlineCapsuleButtonStyle())
            OnboardingPill(label: "Continue", action: onContinue)
                .disabled(model.kinds.isEmpty)
        }
    }

    private func toggle(_ kind: OnboardingKind) {
        withAnimation(reduceMotion ? nil : AaruMotion.ease(AaruMotion.fast)) {
            if model.kinds.contains(kind) {
                model.kinds.remove(kind)
            } else {
                model.kinds.insert(kind)
            }
        }
    }
}

/// One kind, a toggle: Surface at rest, an Accent ring and check when chosen.
private struct KindCard: View {
    let kind: OnboardingKind
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AaruSpace.medium) {
                Image(systemName: kind.mediaKind.symbol)
                    .font(.title2)
                    .foregroundStyle(isOn ? Color(.accent) : Color(.muted))
                    .frame(width: 32)
                Text(kind.label)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color(.accent) : Color(.lineStrong))
            }
            .padding(AaruSpace.large)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(
                isOn ? Color(.accent).opacity(AaruAlpha.tint) : Color(.surface),
                in: .rect(cornerRadius: AaruRadius.panel, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AaruRadius.panel, style: .continuous)
                    .strokeBorder(isOn ? Color(.accent) : Color(.line), lineWidth: isOn ? 2 : 1)
            }
            .contentShape(.rect(cornerRadius: AaruRadius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(HoverLift())
        .accessibilityLabel(kind.label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
