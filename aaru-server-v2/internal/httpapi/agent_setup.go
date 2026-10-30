package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/auth"
	"net/url"
	"strings"
)

// OUT-004 · how to connect each MCP client, written once here so the web and
// Apple apps show the same steps (Swift's AgentSetup). Before a token exists the
// secret is a placeholder; right after minting it is the real one. Committable
// files (`.mcp.json`, `config.toml`) read the secret from AARU_MCP_TOKEN so it
// never lands in a repository.
const (
	agentSetupPlaceholder = "PASTE_YOUR_TOKEN_HERE"
	agentSetupServerName  = "aaru"
	agentSetupEnvVar      = "AARU_MCP_TOKEN"
)

// agentSetupPrompt is what to tell the agent once Aaru is connected.
const agentSetupPrompt = `You are connected to my Aaru library (movies, shows, anime, books) through the "aaru" MCP server. ` +
	`Check it works: call list_airs for what airs this week and read_library for what I'm watching, and ` +
	`tell me in two lines. Use search_titles before adding anything. You may change one item at a time ` +
	`with apply_library_patch if this connection allows changes; anything bigger needs my approval in ` +
	`Aaru, so never say a change was made unless the tool says applied.`

type setupStep = struct {
	Label    string                      `json:"label"`
	Language api.AgentSetupStepsLanguage `json:"language"`
	Note     *string                     `json:"note,omitempty"`
	Text     string                      `json:"text"`
}

func step(label string, language api.AgentSetupStepsLanguage, text string, note ...string) setupStep {
	s := setupStep{Label: label, Language: language, Text: text}
	if len(note) > 0 {
		n := note[0]
		s.Note = &n
	}
	return s
}

func mcpKind(kind auth.TokenKind) (api.AgentMCPKind, bool) {
	switch k := api.AgentMCPKind(kind); k {
	case api.AgentMCPKindClaude, api.AgentMCPKindClaudeCode, api.AgentMCPKindCodex, api.AgentMCPKindGemini,
		api.AgentMCPKindHermes, api.AgentMCPKindOther:
		return k, true
	}
	return "", false
}

// agentSetup is the setup for an MCP kind; false for any other kind. secret nil shows the placeholder.
func agentSetup(kind auth.TokenKind, publicBaseURL *url.URL, secret *string) (api.AgentSetup, bool) {
	dto, ok := mcpKind(kind)
	if !ok {
		return api.AgentSetup{}, false
	}
	endpoint := auth.MCPEndpoint(publicBaseURL)
	token := agentSetupPlaceholder
	if secret != nil {
		token = *secret
	}
	authMode := api.AgentSetupAuthToken
	if kind == auth.KindClaude {
		authMode = api.AgentSetupAuthOauth
	}
	return api.AgentSetup{
		Kind: dto, Title: kind.Label(), Auth: authMode, Url: endpoint,
		Steps: agentSetupSteps(kind, endpoint, token), Prompt: agentSetupPrompt,
	}, true
}

func agentSetupSteps(kind auth.TokenKind, url, token string) []setupStep {
	switch kind {
	case auth.KindClaudeCode:
		return claudeCodeSteps(url, token)
	case auth.KindCodex:
		return codexSteps(url, token)
	case auth.KindHermes:
		return hermesSteps(url, token)
	case auth.KindGemini:
		return geminiSteps(url, token)
	case auth.KindClaude:
		// claude.ai, Claude Desktop and Claude mobile: a custom connector over OAuth, no token.
		return []setupStep{step("In Claude, open Settings → Connectors → Add custom connector", api.AgentSetupStepsLanguageText,
			"Name: Aaru\nURL:  "+url,
			"Then choose Connect: Claude sends you to Aaru to approve. On a Team or Enterprise plan, an owner "+
				"adds the connector for everyone first.")}
	default:
		return []setupStep{step("Any MCP client", api.AgentSetupStepsLanguageText,
			"Transport: streamable HTTP\nURL:       "+url+"\nHeader:    Authorization: Bearer "+token)}
	}
}

func exportStep(token string) setupStep {
	return step("Keep the token in your shell profile", api.AgentSetupStepsLanguageBash, `export `+agentSetupEnvVar+`="`+token+`"`)
}

func mcpServersJSON(url string) string {
	return strings.Join([]string{
		`{`,
		`  "mcpServers": {`,
		`    "` + agentSetupServerName + `": {`,
		`      "type": "http",`,
		`      "url": "` + url + `",`,
		`      "headers": { "Authorization": "Bearer ${` + agentSetupEnvVar + `}" }`,
		`    }`,
		`  }`,
		`}`,
	}, "\n")
}

func claudeCodeSteps(url, token string) []setupStep {
	return []setupStep{
		step("Add Aaru to Claude Code", api.AgentSetupStepsLanguageBash,
			"claude mcp add --transport http "+agentSetupServerName+" "+url+" \\\n  --header \"Authorization: Bearer "+token+"\"",
			"Adds Aaru for you on this machine. Run /mcp in Claude Code to check it is connected. Or leave "+
				"out the header and choose Authenticate in /mcp to approve in Aaru instead of pasting a token."),
		exportStep(token),
		step("Or share it with a project (.mcp.json)", api.AgentSetupStepsLanguageJson, mcpServersJSON(url),
			"Safe to commit: the token comes from "+agentSetupEnvVar+"."),
	}
}

func codexSteps(url, token string) []setupStep {
	return []setupStep{
		exportStep(token),
		step("Add Aaru to Codex", api.AgentSetupStepsLanguageBash,
			"codex mcp add "+agentSetupServerName+" --url "+url+" --bearer-token-env-var "+agentSetupEnvVar),
		step("Or edit ~/.codex/config.toml", api.AgentSetupStepsLanguageToml,
			"[mcp_servers."+agentSetupServerName+"]\nurl = \""+url+"\"\nbearer_token_env_var = \""+agentSetupEnvVar+"\""),
	}
}

func hermesSteps(url, token string) []setupStep {
	return []setupStep{
		step("Add Aaru to Hermes", api.AgentSetupStepsLanguageBash,
			"hermes mcp add "+agentSetupServerName+" --url "+url+" --auth header",
			"When Hermes asks for the header, enter: Authorization: Bearer "+token),
		step("Or edit ~/.hermes/config.yaml", api.AgentSetupStepsLanguageYaml, strings.Join([]string{
			"mcp_servers:",
			"  " + agentSetupServerName + ":",
			"    url: " + url,
			"    headers:",
			`      Authorization: "Bearer ${` + agentSetupEnvVar + `}"`,
			"    enabled: true",
		}, "\n"), "Put "+agentSetupEnvVar+"="+token+" in ~/.hermes/.env."),
	}
}

func geminiSteps(url, token string) []setupStep {
	return []setupStep{
		step("Add Aaru to Gemini CLI", api.AgentSetupStepsLanguageBash,
			"gemini mcp add --scope user --transport http "+agentSetupServerName+" "+url+" \\\n  --header \"Authorization: Bearer "+token+"\""),
		exportStep(token),
		step("Or edit ~/.gemini/settings.json", api.AgentSetupStepsLanguageJson, mcpServersJSON(url)),
	}
}

// MUS-007 · how to point each scrobbler at Aaru's ListenBrainz endpoint (Swift's
// MusicSetup). Only answered right after minting, with the real token in it.

// listenBrainzPath is where the ListenBrainz submit protocol is served.
const listenBrainzPath = "/listenbrainz/1"

// musicScrobblerTitle names a scrobbler; a music token is named for its scrobbler unless the user named it.
func musicScrobblerTitle(s api.MusicScrobbler) string {
	switch s {
	case api.MusicScrobblerWebScrobbler:
		return "Web Scrobbler"
	case api.MusicScrobblerPanoScrobbler:
		return "Pano Scrobbler"
	case api.MusicScrobblerNavidrome:
		return "Navidrome"
	case api.MusicScrobblerJellyfin:
		return "Jellyfin"
	default:
		return "Music scrobbler"
	}
}

func musicScrobbler(dto *api.MusicScrobbler) api.MusicScrobbler {
	if dto != nil {
		switch *dto {
		case api.MusicScrobblerWebScrobbler, api.MusicScrobblerPanoScrobbler, api.MusicScrobblerNavidrome, api.MusicScrobblerJellyfin:
			return *dto
		}
	}
	return api.MusicScrobblerOther
}

type musicField = struct {
	Label string `json:"label"`

	// Secret The token. Clients mask it until copied.
	Secret *bool  `json:"secret,omitempty"`
	Value  string `json:"value"`
}

type musicLink = struct {
	Label string `json:"label"`
	Url   string `json:"url"` //nolint:revive // mirrors the generated type
}

type musicStep = struct {
	// Fields Values to copy, each with the label the scrobbler shows next to its field.
	Fields *[]musicField `json:"fields,omitempty"`
	Link   *musicLink    `json:"link,omitempty"`
	Text   string        `json:"text"`
}

func field(label, value string) musicField { return musicField{Label: label, Value: value} }

func secretField(label, value string) musicField {
	t := true
	return musicField{Label: label, Value: value, Secret: &t}
}

func mstep(text string, fields ...musicField) musicStep {
	s := musicStep{Text: text}
	if len(fields) > 0 {
		s.Fields = &fields
	}
	return s
}

func linkStep(text, label, url string) musicStep {
	return musicStep{Text: text, Link: &musicLink{Label: label, Url: url}}
}

var playStep = mstep("Play a song. It shows up here within a few seconds.")

func musicSetup(scrobbler api.MusicScrobbler, publicBaseURL *url.URL, secret string) api.MusicSetup {
	// `https://api.aaruapp.com/listenbrainz/`, what clients that add `1/submit-listens` want.
	base := auth.AppendPath(publicBaseURL, "listenbrainz") + "/"
	submit := auth.AppendPath(publicBaseURL, strings.TrimPrefix(listenBrainzPath, "/"), "submit-listens")
	token := secretField("Token", secret)
	// Verified against each client's source, 2026-10-21. They disagree on the address:
	// Web Scrobbler wants the submit URL, Pano the root with a slash, Navidrome the root
	// with `1/`, and Jellyfin the root with no slash at all.
	root := strings.TrimSuffix(base, "/")
	var steps []musicStep
	switch scrobbler {
	case api.MusicScrobblerWebScrobbler:
		steps = []musicStep{
			linkStep("Install Web Scrobbler for Chrome, Firefox, Edge or Safari.", "Get Web Scrobbler", "https://web-scrobbler.com"),
			mstep("Open its options, then Accounts. On the ListenBrainz card, choose Use local instance and "+
				"paste these. Don't use Love: it sends the token to listenbrainz.org.", field("API URL", submit), token),
			playStep,
		}
	case api.MusicScrobblerPanoScrobbler:
		steps = []musicStep{
			linkStep("Install Pano Scrobbler on Android, Windows or Linux.", "Get Pano Scrobbler",
				"https://play.google.com/store/apps/details?id=com.arn.scrobble"),
			mstep("In Pano's settings, under Services, choose ListenBrainz-like instance 1. Paste these and verify.",
				field("API URL", base), secretField("Authentication token", secret)),
			playStep,
		}
	case api.MusicScrobblerNavidrome:
		steps = []musicStep{
			mstep("Set this in Navidrome's configuration and restart it. It applies to everyone on that Navidrome server.",
				field("ND_LISTENBRAINZ_BASEURL", base+"1/")),
			mstep("In Navidrome, open your user menu → Personal, turn on Scrobble to ListenBrainz, paste the token and save.", token),
			playStep,
		}
	case api.MusicScrobblerJellyfin:
		steps = []musicStep{
			mstep("In Jellyfin, add this repository under Dashboard → Plugins → Repositories, then install "+
				"ListenBrainz from the catalog and restart.", field("Repository", "https://repo.xkrivo.net/jellyfin/manifest.json")),
			mstep("In the plugin's General tab, set the ListenBrainz API URL. It applies to everyone on that Jellyfin server.",
				field("ListenBrainz API URL", root)),
			mstep("In User Config, pick your user, paste the token, turn on Enable submitting listens and save. "+
				"Leave favorites sync off.", secretField("ListenBrainz API token", secret)),
			playStep,
		}
	default:
		steps = []musicStep{
			mstep("In the app's ListenBrainz settings, use a custom server. Most ask for the server, some for "+
				"the full submit URL. If it wants an address ending in /1/, add that to the server.",
				field("Server", root), field("Submit URL", submit), token),
			playStep,
		}
	}
	return api.MusicSetup{Scrobbler: scrobbler, Title: musicScrobblerTitle(scrobbler), SubmitUrl: submit, BaseUrl: base, Steps: steps}
}
