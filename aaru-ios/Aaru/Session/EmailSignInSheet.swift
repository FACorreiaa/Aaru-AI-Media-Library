import SwiftUI

/// Email sign-in: send a code, type it in. Works before the sign-in link can open the app.
struct EmailSignInSheet: View {
    let flow: AuthFlow

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case email, code }

    var body: some View {
        NavigationStack {
            // Scrolls so the field and its button stay reachable at accessibility text sizes.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(codeSent ? "Check your email" : "Sign in with email")
                        .font(.aaruDisplay(.title))
                    Text(codeSent
                        ? "We sent a six-digit code to \(email). It works once, for 15 minutes."
                        : "We'll email you a six-digit code. No password.")
                        .foregroundStyle(Color(.muted))
                        .fixedSize(horizontal: false, vertical: true)

                    if codeSent {
                        field("Code", text: $code, prompt: "123 456", focus: .code)
                            .textContentType(.oneTimeCode)
                        #if os(iOS)
                            .keyboardType(.numberPad)
                        #endif
                    } else {
                        field("Email", text: $email, prompt: "you@example.com", focus: .email)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                        #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        #endif
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(Color(.danger))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: submit) {
                        ZStack {
                            Text(codeSent ? "Sign in" : "Send code").opacity(isWorking ? 0 : 1)
                            if isWorking {
                                ProgressView()
                            }
                        }
                    }
                    .buttonStyle(OutlineCapsuleButtonStyle())
                    .disabled(isWorking || (codeSent ? code.filter(\.isNumber).count != 6 : !email.contains("@")))

                    if codeSent {
                        Button("Use a different email or send a new code") {
                            codeSent = false
                            code = ""
                            errorMessage = nil
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.paper).ignoresSafeArea())
            .foregroundStyle(Color(.ink))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focus = .email }
            .onSubmit(submit)
        }
    }

    /// Label above the input, error below it.
    private func field(_ label: String, text: Binding<String>, prompt: String, focus field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.callout.weight(.medium))
            TextField(label, text: text, prompt: Text(prompt))
                .focused($focus, equals: field)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Color(.surface), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func submit() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                if codeSent {
                    try await flow.signIn(email: email, code: code)
                    dismiss()
                } else {
                    try await flow.sendCode(to: email)
                    codeSent = true
                    focus = .code
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
