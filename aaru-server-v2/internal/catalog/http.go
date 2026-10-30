package catalog

import (
	"aaru-go-api/internal/provider"
	"context"
	"net/url"
	"slices"
	"strings"
)

// buildURL is base + "/" + path with the query sorted by key, then any extra items
// in order (TMDB's api_key goes last).
func buildURL(base, path string, query map[string]string, extra ...[2]string) string {
	keys := make([]string, 0, len(query))
	for k := range query {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	var parts []string
	for _, k := range keys {
		parts = append(parts, url.QueryEscape(k)+"="+url.QueryEscape(query[k]))
	}
	for _, kv := range extra {
		parts = append(parts, url.QueryEscape(kv[0])+"="+url.QueryEscape(kv[1]))
	}
	u := strings.TrimRight(base, "/") + "/" + strings.TrimLeft(path, "/")
	if len(parts) > 0 {
		u += "?" + strings.Join(parts, "&")
	}
	return u
}

// getJSON decodes a GET with these headers.
func getJSON(ctx context.Context, client *provider.Client, rawURL string, headers [][2]string, v any) error {
	return client.DecodeJSON(ctx, provider.Request{URL: rawURL, Headers: headers}, v)
}
