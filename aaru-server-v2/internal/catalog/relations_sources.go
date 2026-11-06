package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"cmp"
	"context"
	"fmt"
	"slices"
	"strconv"
	"strings"
)

// MARK: - AniList (GRAPH-001): an anime's or manga's own relations

// aniListRelationFields are what a related entry needs to be drawn and opened.
const aniListRelationFields = `id idMal type format title { romaji english native }
startDate { year month day } coverImage { large }`

// aniListRelations maps AniList's relation types onto Aaru's. CHARACTER (shares a character) is
// left out: it links half a franchise and says nothing about order.
var aniListRelations = map[string]core.Relation{
	"PREQUEL": core.RelationPrequel, "SEQUEL": core.RelationSequel, "SIDE_STORY": core.RelationSideStory,
	"SPIN_OFF": core.RelationSpinOff, "ADAPTATION": core.RelationAdaptation, "SOURCE": core.RelationSource,
	"ALTERNATIVE": core.RelationAlternative, "SUMMARY": core.RelationSummary, "COMPILATION": core.RelationSummary,
	"PARENT": core.RelationParent, "CONTAINS": core.RelationOther, "OTHER": core.RelationOther,
}

// RelationSourceName names AniList in the relation cache.
func (a *AniList) RelationSourceName() string { return "anilist" }

// ChainOnly is true: AniList is asked about main-chain titles only; its rate limit (30 a minute while
// degraded) cannot pay for every OVA's and spin-off's own relations.
func (a *AniList) ChainOnly() bool { return true }

// RelationKey is the AniList id; AniList knows nothing without one.
func (a *AniList) RelationKey(n RelatedNode) string {
	if n.IDs.AniList == "" {
		return ""
	}
	return "anilist:" + n.IDs.AniList
}

// Relations are the entry's related anime and manga. Music videos are left out.
func (a *AniList) Relations(ctx context.Context, n RelatedNode) (Relations, error) {
	id, err := strconv.Atoi(n.IDs.AniList)
	if err != nil {
		return Relations{Edges: []RelatedEdge{}}, nil
	}
	var body struct {
		Media *struct {
			aniListMedia
			Relations *struct {
				Edges []struct {
					RelationType string       `json:"relationType"`
					Node         aniListMedia `json:"node"`
				} `json:"edges"`
			} `json:"relations"`
		} `json:"Media"`
	}
	err = a.post(ctx, fmt.Sprintf(`query ($id: Int) {
  Media(id: $id) { %s relations { edges { relationType(version: 2) node { %s } } } }
}`, aniListRelationFields, aniListRelationFields), map[string]any{"id": id}, &body)
	if provider.IsNotFound(err) {
		return Relations{Edges: []RelatedEdge{}}, nil
	}
	if err != nil {
		return Relations{}, err
	}
	out := Relations{Edges: []RelatedEdge{}}
	if body.Media == nil {
		return out, nil
	}
	self := body.Media.relatedNode()
	out.Self = &self
	if body.Media.Relations == nil {
		return out, nil
	}
	for _, e := range body.Media.Relations.Edges {
		relation, ok := aniListRelations[e.RelationType]
		if !ok || sval(e.Node.Format) == "MUSIC" {
			continue
		}
		out.Edges = append(out.Edges, RelatedEdge{To: e.Node.relatedNode(), Relation: relation})
	}
	return out, nil
}

// relatedNode is the entry as a graph node.
func (m aniListMedia) relatedNode() RelatedNode {
	hit := m.hit()
	return RelatedNode{
		Type: hit.Type, IsAnime: hit.IsAnime, IDs: hit.IDs, Title: hit.Title, Year: hit.Year,
		ReleaseDate: hit.ReleaseDate, PosterURL: hit.PosterURL, Format: strings.ToLower(sval(m.Format)),
	}
}

// MARK: - TMDB collections (GRAPH-001): a film's series, in release order

// RelationSourceName names TMDB in the relation cache.
func (t *TMDB) RelationSourceName() string { return "tmdb" }

// RelationKey is a film's TMDB id: only films belong to TMDB collections.
func (t *TMDB) RelationKey(n RelatedNode) string {
	if n.Type != core.MediaMovie || n.IDs.TMDB == "" {
		return ""
	}
	return "tmdb:movie:" + n.IDs.TMDB
}

// Relations are the film's collection as one chain by release date: each part is the sequel of
// the part released before it. Parts not yet dated go last; a film in no collection has none.
func (t *TMDB) Relations(ctx context.Context, n RelatedNode) (Relations, error) {
	var detail struct {
		Collection *struct {
			ID int `json:"id"`
		} `json:"belongs_to_collection"`
	}
	err := t.get(ctx, "movie/"+n.IDs.TMDB, nil, &detail)
	if provider.IsNotFound(err) || (err == nil && detail.Collection == nil) {
		return Relations{Edges: []RelatedEdge{}}, nil
	}
	if err != nil {
		return Relations{}, err
	}
	var collection struct {
		Parts []tmdbDetail `json:"parts"`
	}
	err = t.get(ctx, "collection/"+strconv.Itoa(detail.Collection.ID), nil, &collection)
	if provider.IsNotFound(err) {
		return Relations{Edges: []RelatedEdge{}}, nil
	}
	if err != nil {
		return Relations{}, err
	}
	var parts []RelatedNode
	for _, p := range collection.Parts {
		hit, ok := p.hit(core.MediaMovie)
		if !ok {
			continue
		}
		parts = append(parts, RelatedNode{
			Type: core.MediaMovie, IsAnime: hit.IsAnime, IDs: hit.IDs, Title: hit.Title, Year: hit.Year,
			ReleaseDate: hit.ReleaseDate, PosterURL: hit.PosterURL,
		})
	}
	slices.SortStableFunc(parts, func(a, b RelatedNode) int {
		return cmp.Compare(releaseKey(a), releaseKey(b))
	})
	out := Relations{Edges: []RelatedEdge{}}
	for i := 1; i < len(parts); i++ {
		from := parts[i-1]
		out.Edges = append(out.Edges, RelatedEdge{From: &from, To: parts[i], Relation: core.RelationSequel})
	}
	return out, nil
}
