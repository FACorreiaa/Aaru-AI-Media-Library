import SwiftUI

/// The bottom of the Assistant card: type, or tap the mic and talk. While listening, the field
/// makes way for a level meter; the words go up once Aaru has read them.
struct AssistantComposer: View {
    let model: AssistantModel
    /// Opened by a long press: the mic is about to start, so no keyboard.
    let opensListening: Bool

    @State private var text = ""
    @FocusState private var isFocused: Bool
    @Environment(\.openURL) private var openURL

    private var question: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTooLong: Bool {
        question.unicodeScalars.count > AssistantModel.maxQuestionScalars
    }

    private var canSend: Bool {
        model.phase == .idle && !question.isEmpty && !isTooLong
    }

    /// One muted line above the field. The words stay, so they can be cut down.
    private var problem: String? {
        let showsField = model.phase != .listening && model.phase != .reading
        return showsField && isTooLong ? "That's too long for Aaru. Try something shorter." : model.voiceProblem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.small) {
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            if model.micDenied {
                micDenied
            }
            HStack(alignment: .bottom, spacing: AaruSpace.xsmall) {
                input
                if model.voiceAvailable, model.phase != .reading {
                    micButton
                }
                if model.phase != .listening, model.phase != .reading {
                    sendButton
                }
            }
        }
        .padding(.leading, AaruSpace.medium)
        .padding(.trailing, AaruSpace.xsmall)
        .padding(.vertical, AaruSpace.small)
        .onAppear {
            if !opensListening {
                isFocused = true
            }
        }
    }

    @ViewBuilder private var input: some View {
        switch model.phase {
        case .listening:
            HStack(spacing: AaruSpace.medium) {
                Text("Listening…")
                    .foregroundStyle(Color(.ink))
                LevelMeter(level: model.level)
            }
            .modifier(ComposerField())
        case .reading:
            HStack(spacing: AaruSpace.small) {
                ProgressView().controlSize(.small)
                Text("Reading what you said…")
                    .foregroundStyle(Color(.muted))
                Spacer(minLength: 0)
            }
            .modifier(ComposerField())
        case .idle, .asking, .answering:
            field
        }
    }

    private var field: some View {
        TextField("Ask Aaru", text: $text, axis: .vertical)
            .lineLimit(1 ... 5)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .foregroundStyle(Color(.ink))
            .modifier(ComposerField())
        // Return is a new line on iPhone, where the send button sends.
        #if os(macOS)
            .onSubmit(send)
        #endif
    }

    private var micButton: some View {
        let listening = model.phase == .listening
        return Button {
            model.toggleListening()
        } label: {
            Label(listening ? "Stop and send" : "Talk to Aaru", systemImage: listening ? "stop.fill" : "mic")
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(Color(listening ? .accent : .muted))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(model.phase != .idle && !listening)
        .help(listening ? "Stop and send" : "Talk to Aaru")
    }

    private var sendButton: some View {
        Button(action: send) {
            Label("Send", systemImage: "arrow.up.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(Color(canSend ? .accent : .muted))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help("Send")
    }

    private var micDenied: some View {
        VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
            Text("Aaru can't use the microphone. Turn it on in Settings.")
                .foregroundStyle(Color(.muted))
            Button(openSettingsTitle) {
                if let url = URL(string: Self.micSettingsLink) {
                    openURL(url)
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(Color(.accent))
            .buttonStyle(.plain)
        }
        .font(.footnote)
    }

    private var openSettingsTitle: String {
        #if os(iOS)
            "Open Settings"
        #else
            "Open System Settings"
        #endif
    }

    private static var micSettingsLink: String {
        #if os(iOS)
            UIApplication.openSettingsURLString
        #else
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        #endif
    }

    /// Keeps the words if the model refused them.
    private func send() {
        guard canSend else { return }
        model.send(text)
        if model.phase == .answering {
            text = ""
        }
    }
}

/// The field's shape, the same whatever is in it, so nothing jumps when the mic takes over.
private struct ComposerField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, AaruSpace.medium)
            .padding(.vertical, AaruSpace.small)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .field()
    }
}

/// How loud the mic hears. Information, not decoration: under Reduce Motion it still moves, in steps.
private struct LevelMeter: View {
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(Color(.line))
            .overlay {
                Rectangle()
                    .fill(Color(.accent))
                    .scaleEffect(x: CGFloat(max(level, 0.02)), anchor: .leading)
            }
            .clipShape(.capsule)
            .frame(height: 6)
            .animation(reduceMotion ? nil : .linear(duration: 0.1), value: level)
            .accessibilityHidden(true)
    }
}
