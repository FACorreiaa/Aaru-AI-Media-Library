import SwiftUI

/// The owl's poses (BRD-004, `docs/brand/owl_poses.py`): standing is the poster's owl; curious
/// when nothing matches, sleeping when nothing airs, celebrating for a milestone.
enum OwlPose {
    case standing, curious, sleeping, celebrating

    var image: ImageResource {
        switch self {
        case .standing: .mascot
        case .curious: .owlCurious
        case .sleeping: .owlSleeping
        case .celebrating: .owlCelebrating
        }
    }
}

/// Aaru's owl (DESIGN.md "Brand"): the whole owl on the night disc, the poster's sky, so the white
/// owl reads in light and dark. Decorative by default; a signed-out screen that introduces the
/// owl passes a label. `idle` gives it the slow idle life (`OwlIdleLife`); recap cards, errors
/// and anything rendered to an image stay still.
struct OwlMedallion: View {
    /// The disc's diameter. Nil: as wide as offered, square.
    var size: CGFloat?
    var idle = false
    var pose = OwlPose.standing
    private var label: Text?

    init(size: CGFloat? = nil, idle: Bool = false, pose: OwlPose = .standing) {
        self.size = size
        self.idle = idle
        self.pose = pose
    }

    /// The owl as content, for a screen that introduces it (Welcome).
    init(label: Text, size: CGFloat? = nil, idle: Bool = false) {
        self.label = label
        self.size = size
        self.idle = idle
    }

    var body: some View {
        if let label {
            disc.owlIdleLife(idle)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isImage)
        } else {
            disc.owlIdleLife(idle).accessibilityHidden(true)
        }
    }

    private var disc: some View {
        ZStack {
            Circle().fill(Color(.night))
            Image(pose.image)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                // The owl stands on the disc's lower edge: room above its ears, none below.
                .padding(.top, size.map { $0 * 0.07 } ?? 10)
        }
        .frame(width: size, height: size)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
    }
}

/// The owl's head on the night disc: the small mark for rows and headings. Always decorative.
/// `AgentPresence` and `AaruAvatar` draw the same head with their own "working" breath.
struct OwlHead: View {
    let size: CGFloat
    var idle = false

    var body: some View {
        Image(.owlMark)
            .renderingMode(.original)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .background(Color(.night))
            .clipShape(Circle())
            .owlIdleLife(idle)
            .accessibilityHidden(true)
    }
}

/// A screen with nothing to show yet, with the owl: the native `ContentUnavailableView`, its
/// title, message and actions unchanged, with `OwlMedallion` in place of the symbol. For whole
/// screens only; pickers, sheets' inner lists and errors keep the plain view.
struct OwlUnavailableView<Actions: View>: View {
    private let title: Text
    private let message: Text?
    private let pose: OwlPose
    private let actions: Actions

    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        pose: OwlPose = .standing,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = Text(title)
        self.message = message.map { Text($0) }
        self.pose = pose
        self.actions = actions()
    }

    init(
        title: some StringProtocol,
        message: (some StringProtocol)? = String?.none,
        pose: OwlPose = .standing,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = Text(title)
        self.message = message.map { Text($0) }
        self.pose = pose
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                OwlMedallion(size: 96, idle: true, pose: pose)
                    .padding(.bottom, 4)
            }
        } description: {
            if let message {
                message
            }
        } actions: {
            actions
        }
    }
}

extension OwlUnavailableView where Actions == EmptyView {
    init(title: LocalizedStringKey, message: LocalizedStringKey? = nil, pose: OwlPose = .standing) {
        self.init(title: title, message: message, pose: pose) { EmptyView() }
    }

    init(title: some StringProtocol, message: (some StringProtocol)? = String?.none, pose: OwlPose = .standing) {
        self.init(title: title, message: message, pose: pose) { EmptyView() }
    }
}

/// The idle life: a slow float of 3pt (6 s each way) and an amber glow behind the disc that
/// swells and fades on its own 4 s beat, so the two never line up into a rhythm. Calmer than
/// "Aaru is working" (`AgentPresence`, `AaruAvatar`), which breathes in under 2.5 s. Still under
/// Reduce Motion, and turning it on mid-float stops the owl at rest.
private struct OwlIdleLife: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false
    @State private var glowing = false

    func body(content: Content) -> some View {
        content
            .background {
                OwlGlow().opacity(reduceMotion ? 0.4 : glowing ? 0.6 : 0.25)
            }
            .offset(y: floating && !reduceMotion ? -3 : 0)
            .onAppear(perform: start)
            .onDisappear(perform: rest)
            .onChange(of: reduceMotion) { _, reduce in
                if reduce {
                    rest()
                } else {
                    start()
                }
            }
    }

    private func start() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { floating = true }
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { glowing = true }
    }

    /// Back to rest at once: a plain state change ends the repeating animations.
    private func rest() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            floating = false
            glowing = false
        }
    }
}

/// Amber light around the disc: Gold fading to nothing past the disc's edge.
private struct OwlGlow: View {
    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            RadialGradient(
                colors: [Color(.gold).opacity(0.35), Color(.gold).opacity(0)],
                center: .center,
                startRadius: diameter * 0.42,
                endRadius: diameter * 0.8
            )
            .frame(width: diameter * 1.6, height: diameter * 1.6)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder func owlIdleLife(_ idle: Bool) -> some View {
        if idle {
            modifier(OwlIdleLife())
        } else {
            self
        }
    }
}

#Preview("Owl") {
    VStack(spacing: 32) {
        HStack(spacing: 24) {
            OwlHead(size: 40, idle: true)
            OwlHead(size: 28)
            OwlMedallion(size: 96, idle: true)
        }
        HStack(spacing: 24) {
            OwlMedallion(size: 96, pose: .curious)
            OwlMedallion(size: 96, pose: .sleeping)
            OwlMedallion(size: 96, pose: .celebrating)
        }
        OwlUnavailableView(title: "Your library is empty", message: "Search for a film, show, anime, book or album.") {
            Button("Search") {}.buttonStyle(.borderedProminent)
        }
    }
    .padding()
    .background(Color(.paper))
}
