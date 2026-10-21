import AaruAPI
import SwiftUI

/// Connect one MCP client: pick it, read its steps (GET /v1/agent/setup/{kind}), then create
/// a token. The server answers the same steps with the token filled in; they are shown once.
struct ConnectionSetupView: View {
    typealias Kind = Components.Schemas.AgentMCPKind

    let api: Client
    var onCreated: (Components.Schemas.AgentTokenCreated) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .claude
    @State private var name = ""
    @State private var allowsLibraryWrites = false
    @State private var allowsImports = false
    @State private var preview: Components.Schemas.AgentSetup?
    @State private var created: Components.Schemas.AgentTokenCreated?
    @State private var working = false
    @State private var problem: String?
    @State private var copiedStep: String?

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    Section {
                        Text(
                            "Your token is in the steps below. Anyone with it can read your library, so treat it "
                                + "like a password; Aaru shows it only now."
                        )
                        .font(.callout)
                    }
                    if let setup = created.setup {
                        steps(setup)
                    }
                } else {
                    Section("Agent") {
                        Picker("Agent", selection: $kind) {
                            ForEach(Kind.allCases, id: \.self) { kind in
                                Text(Self.label(kind.rawValue)).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        if !connectsOverOAuth {
                            TextField("Name", text: $name, prompt: Text(Self.label(kind.rawValue)))
                            Toggle(isOn: $allowsLibraryWrites) {
                                Text("Allow changes")
                                Text("One item at a time, as a tap would. Bigger changes wait for your approval.")
                            }
                            Toggle(isOn: $allowsImports) {
                                Text("Allow imports")
                                Text("It can hand Aaru a list to import. You review it here before anything is added.")
                            }
                        }
                    }
                    if !connectsOverOAuth {
                        Section {
                            Button {
                                Task { await create() }
                            } label: {
                                HStack {
                                    Text("Connect \(Self.label(kind.rawValue))")
                                    if working {
                                        Spacer()
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(working)
                        }
                    }
                    if let preview {
                        steps(preview)
                    }
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Connect an agent")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(created == nil ? "Cancel" : "Done") { dismiss() }
                    }
                }
                .task(id: kind) { await loadPreview() }
        }
        // A token shown once must not vanish on a stray swipe.
        .interactiveDismissDisabled(created != nil)
    }

    /// Claude asks for approval in Aaru itself: no token to make here, only the steps.
    private var connectsOverOAuth: Bool {
        kind == .claude || preview?.auth == .oauth
    }

    @ViewBuilder
    private func steps(_ setup: Components.Schemas.AgentSetup) -> some View {
        ForEach(Array(setup.steps.enumerated()), id: \.offset) { _, step in
            Section {
                Text(step.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                copyButton(step.text)
            } header: {
                Text(step.label)
            } footer: {
                if let note = step.note {
                    Text(note)
                }
            }
        }
        Section("Then ask your agent") {
            Text(setup.prompt).font(.footnote).textSelection(.enabled)
            copyButton(setup.prompt)
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            #if os(iOS)
                UIPasteboard.general.string = text
            #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            #endif
            copiedStep = text
        } label: {
            Label(copiedStep == text ? "Copied" : "Copy", systemImage: copiedStep == text ? "checkmark" : "doc.on.doc")
        }
    }

    private func loadPreview() async {
        preview = nil
        do {
            if case let .ok(response) = try await api.getAgentSetup(path: .init(kind: kind)) {
                preview = try response.body.json
            }
        } catch {
            // The steps are a convenience; creating still works without them.
        }
    }

    private func create() async {
        working = true
        problem = nil
        defer { working = false }
        guard let tokenKind = Components.Schemas.AgentTokenKind(rawValue: kind.rawValue) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Components.Schemas.AgentTokenCreate(
            kind: tokenKind, name: trimmed.isEmpty ? nil : trimmed, allowLibraryWrites: allowsLibraryWrites,
            allowImports: allowsImports
        )
        do {
            switch try await api.createAgentToken(body: .json(body)) {
            case let .created(response):
                let result = try response.body.json
                created = result
                onCreated(result)
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The connection could not be created."
            }
        } catch {
            problem = "The connection could not be created. Aaru could not reach the server."
        }
    }

    static func label(_ kind: String) -> String {
        switch kind {
        case "claude": "Claude"
        case "claude_code": "Claude Code"
        case "codex": "Codex"
        case "hermes": "Hermes"
        case "gemini": "Gemini CLI"
        case "stremio": "Stremio"
        case "browser": "Browser extension"
        case "music": "Music scrobbler"
        default: "MCP client"
        }
    }

    static func label(_ kind: Components.Schemas.AgentTokenKind) -> String {
        label(kind.rawValue)
    }
}
