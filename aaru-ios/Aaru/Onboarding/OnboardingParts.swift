import AaruCore
import SwiftUI

/// One first-run screen (DESIGN.md §0a): Back and Skip in a bar at the top, a big headline, the
/// step's content scrolling under it, and the step's pill fixed at the bottom.
struct OnboardingPage<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String?
    /// Nil on the first screen.
    var onBack: (() -> Void)?
    let onSkip: () -> Void
    var isBusy = false
    /// The owl (curious) above the headline: the first screen only, the one place in the flow.
    var showsOwl = false
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AaruSpace.section) {
                VStack(alignment: .leading, spacing: AaruSpace.small) {
                    if showsOwl {
                        OwlMedallion(size: 96, pose: .curious)
                            .padding(.bottom, AaruSpace.small)
                    }
                    Text(title)
                        .font(.aaruDisplay(.largeTitle, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(Color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                content()
            }
            .padding(.top, AaruSpace.small)
            .padding(.bottom, AaruSpace.xxlarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: AaruSpace.medium) { footer() }
                .frame(maxWidth: 520)
                .padding(.horizontal, 20)
                .padding(.top, AaruSpace.medium)
                .padding(.bottom, AaruSpace.small)
                .frame(maxWidth: .infinity)
                .background(Color(.paper))
        }
        .background(Color(.paper).ignoresSafeArea())
        .foregroundStyle(Color(.ink))
    }

    private var topBar: some View {
        HStack {
            if let onBack {
                Button("Back", systemImage: "chevron.backward", action: onBack)
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
            Button("Skip", action: onSkip)
                .accessibilityHint("Ends setup. What you saved stays.")
        }
        .font(.body.weight(.medium))
        .buttonStyle(.borderless)
        .disabled(isBusy)
        .padding(.horizontal, 20)
        .padding(.vertical, AaruSpace.medium)
        .background(Color(.paper))
    }
}

/// The step's main pill: Accent, full width. Its quiet partner is `OutlineCapsuleButtonStyle`.
struct FilledCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color(.onAccent))
            .background(Color(.accent), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : AaruAlpha.half)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// The pill, with a spinner in place of its words while the step saves.
struct OnboardingPill: View {
    let label: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isBusy {
                ProgressView().tint(Color(.onAccent))
            } else {
                Text(label)
            }
        }
        .buttonStyle(FilledCapsuleButtonStyle())
        .disabled(isBusy)
        .accessibilityLabel(label)
    }
}

/// A failed save or load on a step, in the danger colour over the pill; a tap dismisses it.
struct OnboardingProblem: View {
    let message: String?
    let onDismiss: () -> Void

    var body: some View {
        if let message {
            Button(action: onDismiss) {
                Label(message, systemImage: "exclamationmark.arrow.circlepath")
                    .font(.callout)
                    .foregroundStyle(Color(.danger))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Dismisses this message")
        }
    }
}

/// What a poster in the flow is: open to pick, picked with a status, or in the library already
/// (a row marked it, or it was saved on an earlier screen), which a tap no longer changes.
enum OnboardingPosterState: Equatable {
    case open
    case picked(LibraryStatus)
    case saved(LibraryStatus)
    case inLibrary
}

/// A poster card for the first run: the art, the name and year under it, and the status chip on
/// the art once picked. A tap cycles the status; a hold (right-click on the Mac) offers the
/// statuses and Remove.
struct OnboardingPoster: View {
    let hit: CatalogHit
    let kind: MediaKind
    let state: OnboardingPosterState
    /// A row's fixed width; nil fills a grid cell.
    var width: CGFloat?
    /// What the hold menu offers. Related titles are planned or not, so they offer only that.
    var menuStatuses = LibraryStatus.addable
    /// What a tap does, for VoiceOver, when it is not the status cycle.
    var tapHint: String?
    let onTap: () -> Void
    /// A status from the menu, or nil for Remove.
    let onSet: (LibraryStatus?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: LibraryStatus? {
        switch state {
        case let .picked(status), let .saved(status): status
        case .open, .inLibrary: nil
        }
    }

    private var isLocked: Bool {
        switch state {
        case .saved, .inLibrary: true
        case .open, .picked: false
        }
    }

    var body: some View {
        Button(action: onTap) { card }
            .buttonStyle(.plain)
            .disabled(isLocked)
            .contextMenu {
                if !isLocked {
                    ForEach(menuStatuses) { option in
                        Button {
                            onSet(option)
                        } label: {
                            if option == status {
                                Label(option.label(for: kind), systemImage: "checkmark")
                            } else {
                                Text(option.label(for: kind))
                            }
                        }
                    }
                    if status != nil {
                        Divider()
                        Button("Remove", systemImage: "minus.circle", role: .destructive) { onSet(nil) }
                    }
                }
            }
            .modifier(HoverLift())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([hit.title, hit.year.map(String.init)].compactMap(\.self).joined(separator: ", "))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isLocked ? "" : accessibilityHint)
            .accessibilityAddTraits(status != nil ? [.isButton, .isSelected] : .isButton)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: hit.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .overlay {
                    if status != nil {
                        RoundedRectangle(cornerRadius: AaruRadius.field, style: .continuous)
                            .strokeBorder(Color(.accent), lineWidth: 3)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let status {
                        HomeChip(
                            text: status.label(for: kind),
                            tint: Color(.accent),
                            foreground: Color(.onAccent)
                        )
                        .padding(6)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isLocked {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(.onAccent))
                            .frame(width: 26, height: 26)
                            .background(Color(.accent), in: Circle())
                            .padding(6)
                    }
                }
                .animation(reduceMotion ? nil : AaruMotion.ease(AaruMotion.fast), value: status)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
            }
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The year; an album leads with its artist, a book adds its author.
    private var detail: String? {
        let year = hit.year.map(String.init)
        let parts = switch kind {
        case .music: [hit.byline, year]
        case .book, .manga: [year, hit.byline]
        case .film, .show, .anime: [year]
        }
        let present = parts.compactMap(\.self)
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }

    private var accessibilityValue: String {
        switch state {
        case .open: ""
        case let .picked(status): status.label(for: kind)
        case let .saved(status): "\(status.label(for: kind)), saved"
        case .inLibrary: "In your library"
        }
    }

    private var accessibilityHint: String {
        if let tapHint {
            return "\(tapHint). Touch and hold for the menu."
        }
        let next = Onboarding.nextStatus(status.map(Onboarding.coreStatus), kind: OnboardingKind(kind))
        let tap = next.map { "Marks it \(Onboarding.apiStatus($0).label(for: kind))" } ?? "Takes it off"
        return "\(tap). Touch and hold for a status."
    }
}
