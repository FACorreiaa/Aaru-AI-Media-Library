import AaruAPI
import SwiftUI

/// The unlock (DESIGN.md §17): a quiet toast at the top with the medallion and "Night Owl ·
/// earned", a success haptic, and a tap that opens Achievements. Several at once are one toast;
/// an import or the first run is one summary. A top tier reached live gets `BadgeReveal`, once.
/// No push.
struct UnlockToastModifier: ViewModifier {
    let model: ProgressModel
    @State private var opensShelf = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .overlay(alignment: .top) {
                if let unlock = model.unlock, model.reveal == nil {
                    UnlockToast(unlock: unlock) {
                        model.unlock = nil
                        opensShelf = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task(id: unlock.id) {
                        try? await Task.sleep(for: .seconds(5))
                        if model.unlock == unlock {
                            model.unlock = nil
                        }
                    }
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4), value: model.unlock)
            .sensoryFeedback(.success, trigger: model.unlock) { _, new in new != nil }
            .sheet(item: $model.reveal) { award in
                BadgeReveal(award: award) {
                    model.reveal = nil
                    model.unlock = nil
                }
            }
            .sheet(isPresented: $opensShelf) {
                NavigationStack {
                    AchievementsView(model: model)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { opensShelf = false }
                            }
                        }
                }
            }
    }
}

extension View {
    /// Hosts the unlock toast and the top-tier reveal over the signed-in app.
    func unlockToast(_ model: ProgressModel) -> some View {
        modifier(UnlockToastModifier(model: model))
    }
}

extension Components.Schemas.BadgeAward: @retroactive Identifiable {}

private struct UnlockToast: View {
    let unlock: ProgressModel.Unlock
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                if let award = unlock.award {
                    BadgeMedallion(badge: award.badge, family: award.family, tier: award.tier, size: 36)
                } else {
                    // A summary (an import, the first run) has no one badge to show: the owl celebrates.
                    OwlMedallion(size: 36, pose: .celebrating)
                }
                VStack(alignment: .leading, spacing: 1) {
                    if let award = unlock.award, let word = BadgeGlyph.tierWord(award.tier, of: award.maxTier) {
                        Text(word).eyebrow()
                    }
                    Text(unlock.message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(.ink))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 440)
            .background(Color(.surface), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.line)))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unlock.message)
        .accessibilityHint("Opens Achievements")
    }
}

/// A top tier, once: the medallion settles into place on a full card (a spring; a cross-fade
/// under Reduce Motion).
struct BadgeReveal: View {
    let award: BadgeAward
    let onDone: () -> Void
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            BadgeMedallion(badge: award.badge, family: award.family, tier: award.tier, size: 132)
                // Aaru celebrates it with you (owner, 2026-10-23), as on the web.
                .overlay(alignment: .bottomTrailing) {
                    OwlMedallion(size: 56, pose: .celebrating)
                        .padding(3)
                        .background(Color(.paper), in: Circle())
                        .offset(x: 14, y: 6)
                }
                .scaleEffect(settled || reduceMotion ? 1 : 0.6)
                .opacity(settled ? 1 : 0)
            VStack(spacing: 6) {
                if let word = BadgeGlyph.tierWord(award.tier, of: award.maxTier) {
                    Text(word).eyebrow()
                }
                Text(award.name)
                    .font(.aaruDisplay(.largeTitle, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(award.maxTier > 1 ? "Every tier, earned." : "A hidden one, found.")
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                    .multilineTextAlignment(.center)
            }
            .opacity(settled ? 1 : 0)
            Spacer()
            Button(action: onDone) {
                Text("Done").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(.ink))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.paper))
        .accessibilityElement(children: .contain)
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.6, dampingFraction: 0.7)) {
                settled = true
            }
        }
        .presentationDetents([.large])
    }
}
