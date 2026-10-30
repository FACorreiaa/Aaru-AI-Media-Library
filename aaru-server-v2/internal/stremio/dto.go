package stremio

// The Stremio addon protocol's response shapes (github.com/Stremio/stremio-addon-sdk/docs). Swift sent
// them with sorted keys, so every struct here lists its fields in key order; nil optionals are left out.

// Manifest is the addon's manifest.
type Manifest struct {
	BehaviorHints BehaviorHints     `json:"behaviorHints"`
	Catalogs      []ManifestCatalog `json:"catalogs"`
	Description   string            `json:"description"`
	ID            string            `json:"id"`
	IDPrefixes    []string          `json:"idPrefixes"`
	Logo          *string           `json:"logo,omitempty"`
	Name          string            `json:"name"`
	Resources     []Resource        `json:"resources"`
	Types         []string          `json:"types"`
	Version       string            `json:"version"`
}

// Resource is one resource the addon serves.
type Resource struct {
	IDPrefixes []string `json:"idPrefixes,omitempty"`
	Name       string   `json:"name"`
	Types      []string `json:"types"`
}

// CatalogExtra is an extra a catalog takes.
type CatalogExtra struct {
	Name string `json:"name"`
}

// ManifestCatalog is one catalog the manifest lists.
type ManifestCatalog struct {
	Extra []CatalogExtra `json:"extra,omitempty"`
	ID    string         `json:"id"`
	Name  string         `json:"name"`
	Type  string         `json:"type"`
}

// BehaviorHints says the addon can be configured.
type BehaviorHints struct {
	Configurable          bool `json:"configurable"`
	ConfigurationRequired bool `json:"configurationRequired"`
}

// MetaPreview is one catalog row.
type MetaPreview struct {
	Background  *string `json:"background,omitempty"`
	Description *string `json:"description,omitempty"`
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Poster      *string `json:"poster,omitempty"`
	ReleaseInfo *string `json:"releaseInfo,omitempty"`
	Type        string  `json:"type"`
}

// CatalogResponse is a catalog's answer.
type CatalogResponse struct {
	Metas []MetaPreview `json:"metas"`
}

// MetaVideo is one episode of a meta.
type MetaVideo struct {
	Episode   int     `json:"episode"`
	ID        string  `json:"id"`
	Overview  *string `json:"overview,omitempty"`
	Released  string  `json:"released"`
	Season    int     `json:"season"`
	Thumbnail *string `json:"thumbnail,omitempty"`
	Title     string  `json:"title"`
}

// Meta is a title's details.
type Meta struct {
	Background  *string      `json:"background,omitempty"`
	Description *string      `json:"description,omitempty"`
	ID          string       `json:"id"`
	Name        string       `json:"name"`
	Poster      *string      `json:"poster,omitempty"`
	ReleaseInfo *string      `json:"releaseInfo,omitempty"`
	Type        string       `json:"type"`
	Videos      *[]MetaVideo `json:"videos,omitempty"`
}

// MetaResponse is a meta's answer.
type MetaResponse struct {
	Meta Meta `json:"meta"`
}

// Message is the body of an error or an event acknowledgement; Stremio ignores event bodies.
type Message struct {
	Err *string `json:"err,omitempty"`
}

// Err is an error message body.
func Err(message string) Message { return Message{Err: &message} }
