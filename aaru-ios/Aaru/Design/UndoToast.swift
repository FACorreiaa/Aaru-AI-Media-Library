import Observation
import SwiftUI

/// Something was written (a success haptic), nothing was ("Already caught up"), or the write
/// failed.
enum ToastTone {
    case done, quiet, problem
}

/// The undo toast (PROG-005, DESIGN.md §9): one line at the bottom after a bulk tap, "Marked 62
/// episodes of Severance · Undo", for about six seconds. Until the undo ribbon exists, this is
/// how a whole-show mark is taken back. One center for the app, in the environment, so the
/// toast follows the tap to whichever screen is in front.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let tone: ToastTone
        /// Reverts the write; returns what went wrong, or nil when it was undone.
        let undo: (@MainActor () async -> String?)?
    }

    private(set) var current: Toast?
    private(set) var isUndoing = false

    @ObservationIgnored private var expiry: Task<Void, Never>?

    static let duration: Duration = .seconds(6)

    func show(_ message: String, tone: ToastTone = .done, undo: (@MainActor () async -> String?)? = nil) {
        let toast = Toast(message: message, tone: tone, undo: undo)
        current = toast
        AccessibilityNotification.Announcement(undo == nil ? message : "\(message). Undo is available.").post()
        let id = toast.id
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }

    /// Hides the toast, or only the one with `id` when it is still showing.
    func dismiss(_ id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        current = nil
    }

    func undo() async {
        guard let toast = current, let undo = toast.undo, !isUndoing else { return }
        isUndoing = true
        expiry?.cancel()
        let problem = await undo()
        isUndoing = false
        if let problem {
            show(problem, tone: .problem)
        } else {
            dismiss(toast.id)
            AccessibilityNotification.Announcement("Undone").post()
        }
    }
}

/// The toast itself: Ink, the message, and Undo when the write can be taken back.
struct UndoToast: View {
    let toast: ToastCenter.Toast
    let isUndoing: Bool
    let onUndo: () -> Void
    let onDismiss: () -> Void

    private var symbol: String {
        switch toast.tone {
        case .done: "checkmark.circle.fill"
        case .quiet: "checkmark.circle"
        case .problem: "exclamationmark.arrow.circlepath"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Label(toast.message, systemImage: symbol)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            if toast.undo != nil {
                Button("Undo", action: onUndo)
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .disabled(isUndoing)
            }
        }
        .foregroundStyle(Color(.paper))
        .padding(.leading, 16)
        .padding(.trailing, toast.undo == nil ? 16 : 8)
        .padding(.vertical, toast.undo == nil ? 12 : 2)
        .frame(maxWidth: 560)
        .background(
            toast.tone == .problem ? Color(.danger) : Color(.ink),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// The undo toast at the bottom of a screen, like `ProblemBanner`. Each screen that can make
    /// a bulk write carries one; the center decides what shows.
    func undoToast() -> some View {
        modifier(UndoToastInset())
    }

    /// Puts the center in the environment, with the toast's haptic once for the whole app:
    /// success when something was written, error when it failed, nothing for "Already caught up".
    func toastCenter(_ toasts: ToastCenter) -> some View {
        environment(toasts).sensoryFeedback(trigger: toasts.current?.id) { _, new in
            guard new != nil, let tone = toasts.current?.tone else { return nil }
            switch tone {
            case .done: return .success
            case .problem: return .error
            case .quiet: return nil
            }
        }
    }
}

private struct UndoToastInset: ViewModifier {
    /// Nil in previews.
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            VStack {
                if let toasts, let toast = toasts.current {
                    UndoToast(
                        toast: toast,
                        isUndoing: toasts.isUndoing,
                        onUndo: { Task { await toasts.undo() } },
                        onDismiss: { toasts.dismiss() }
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: toasts?.current?.id)
        }
    }
}
