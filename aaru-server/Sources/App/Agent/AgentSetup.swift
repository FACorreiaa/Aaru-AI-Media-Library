import aaruAPI
import Foundation

/// OUT-004 · how to connect each MCP client, written once here so the web and Apple apps show
/// the same steps. Before a token exists the secret is a placeholder; right after minting it
/// is the real one. Committable files (`.mcp.json`, `config.toml`) read the secret from
/// `AARU_MCP_TOKEN` so it never lands in a repository.
enum AgentSetup {
    static let placeholder = "PASTE_YOUR_TOKEN_HERE"
    static let serverName = "aaru"
    static let envVar = "AARU_MCP_TOKEN"

    static func endpoint(_ publicBaseURL: URL) -> String {
        publicBaseURL.appendingPathComponent("v1").appendingPathComponent("mcp").absoluteString
    }

    static func setup(
        for kind: AgentTokenKind,
        publicBaseURL: URL,
        secret: String? = nil
    ) -> Components.Schemas.AgentSetup? {
        guard let dto = Components.Schemas.AgentMCPKind(rawValue: kind.rawValue) else { return nil }
        let url = endpoint(publicBaseURL)
        let token = secret ?? placeholder
        return Components.Schemas.AgentSetup(
            kind: dto, title: kind.label, auth: kind == .claude ? .oauth : .token, url: url,
            steps: steps(kind, url: url, token: token), prompt: prompt
        )
    }

    typealias Step = Components.Schemas.AgentSetup.StepsPayloadPayload

    private static func steps(_ kind: AgentTokenKind, url: String, token: String) -> [Step] {
        switch kind {
        case .claudeCode: claudeCode(url: url, token: token)
        case .codex: codex(url: url, token: token)
        case .hermes: hermes(url: url, token: token)
        case .gemini: gemini(url: url, token: token)
        case .claude: claude(url: url)
        case .other, .stremio, .browser: [
                Step(label: "Any MCP client", language: .text, text: """
                Transport: streamable HTTP
                URL:       \(url)
                Header:    Authorization: Bearer \(token)
                """),
            ]
        }
    }

    /// claude.ai, Claude Desktop and Claude mobile: a custom connector over OAuth, no token.
    private static func claude(url: String) -> [Step] {
        [
            Step(label: "In Claude, open Settings → Connectors → Add custom connector", language: .text, text: """
            Name: Aaru
            URL:  \(url)
            """, note: """
            Then choose Connect: Claude sends you to Aaru to approve. On a Team or Enterprise plan, an owner \
            adds the connector for everyone first.
            """),
        ]
    }

    private static func export(_ token: String) -> Step {
        Step(label: "Keep the token in your shell profile", language: .bash, text: """
        export \(envVar)="\(token)"
        """)
    }

    private static func claudeCode(url: String, token: String) -> [Step] {
        [
            Step(label: "Add Aaru to Claude Code", language: .bash, text: """
            claude mcp add --transport http \(serverName) \(url) \\
              --header "Authorization: Bearer \(token)"
            """, note: """
            Adds Aaru for you on this machine. Run /mcp in Claude Code to check it is connected. Or leave \
            out the header and choose Authenticate in /mcp to approve in Aaru instead of pasting a token.
            """),
            export(token),
            Step(label: "Or share it with a project (.mcp.json)", language: .json, text: """
            {
              "mcpServers": {
                "\(serverName)": {
                  "type": "http",
                  "url": "\(url)",
                  "headers": { "Authorization": "Bearer ${\(envVar)}" }
                }
              }
            }
            """, note: "Safe to commit: the token comes from \(envVar)."),
        ]
    }

    private static func codex(url: String, token: String) -> [Step] {
        [
            export(token),
            Step(label: "Add Aaru to Codex", language: .bash, text: """
            codex mcp add \(serverName) --url \(url) --bearer-token-env-var \(envVar)
            """),
            Step(label: "Or edit ~/.codex/config.toml", language: .toml, text: """
            [mcp_servers.\(serverName)]
            url = "\(url)"
            bearer_token_env_var = "\(envVar)"
            """),
        ]
    }

    private static func hermes(url: String, token: String) -> [Step] {
        [
            Step(label: "Add Aaru to Hermes", language: .bash, text: """
            hermes mcp add \(serverName) --url \(url) --auth header
            """, note: "When Hermes asks for the header, enter: Authorization: Bearer \(token)"),
            Step(label: "Or edit ~/.hermes/config.yaml", language: .yaml, text: """
            mcp_servers:
              \(serverName):
                url: \(url)
                headers:
                  Authorization: "Bearer ${\(envVar)}"
                enabled: true
            """, note: "Put \(envVar)=\(token) in ~/.hermes/.env."),
        ]
    }

    private static func gemini(url: String, token: String) -> [Step] {
        [
            Step(label: "Add Aaru to Gemini CLI", language: .bash, text: """
            gemini mcp add --scope user --transport http \(serverName) \(url) \\
              --header "Authorization: Bearer \(token)"
            """),
            export(token),
            Step(label: "Or edit ~/.gemini/settings.json", language: .json, text: """
            {
              "mcpServers": {
                "\(serverName)": {
                  "type": "http",
                  "url": "\(url)",
                  "headers": { "Authorization": "Bearer ${\(envVar)}" }
                }
              }
            }
            """),
        ]
    }

    /// What to tell the agent once Aaru is connected.
    static let prompt = """
    You are connected to my Aaru library (movies, shows, anime, books) through the "aaru" MCP server. \
    Check it works: call list_airs for what airs this week and read_library for what I'm watching, and \
    tell me in two lines. Use search_titles before adding anything. You may change one item at a time \
    with apply_library_patch if this connection allows changes; anything bigger needs my approval in \
    Aaru, so never say a change was made unless the tool says applied.
    """
}
