package social

import (
	"aaru-go-api/internal/core"
	"context"
	"fmt"

	"github.com/google/uuid"
)

// FAV-001 (FavoriteService.swift): an ordered top 10 per kind, any catalog title. Profile data
// like the handle: not a library write and not journaled. A friend sees it only while the user
// shares their library.

// FavoriteLimit is a top 10.
const FavoriteLimit = 10

// FavoriteKind is one of the six kinds a user keeps favorites for. Anime is a flag on movie and
// show, so the kind is stored rather than read from the title's type.
type FavoriteKind string

// The favorite kinds.
const (
	FavoriteFilm  FavoriteKind = "film"
	FavoriteShow  FavoriteKind = "show"
	FavoriteAnime FavoriteKind = "anime"
	FavoriteManga FavoriteKind = "manga"
	FavoriteBook  FavoriteKind = "book"
	FavoriteAlbum FavoriteKind = "album"
)

// Valid reports one of the six kinds.
func (k FavoriteKind) Valid() bool {
	switch k {
	case FavoriteFilm, FavoriteShow, FavoriteAnime, FavoriteManga, FavoriteBook, FavoriteAlbum:
		return true
	}
	return false
}

// KindOf is the kind a title counts as.
func KindOf(t core.Title) FavoriteKind {
	switch t.Type {
	case core.MediaMovie:
		if t.IsAnime {
			return FavoriteAnime
		}
		return FavoriteFilm
	case core.MediaShow:
		if t.IsAnime {
			return FavoriteAnime
		}
		return FavoriteShow
	case core.MediaManga:
		return FavoriteManga
	case core.MediaBook:
		return FavoriteBook
	default:
		return FavoriteAlbum
	}
}

func article(kind FavoriteKind) string {
	switch kind {
	case FavoriteFilm:
		return "a film"
	case FavoriteShow:
		return "a show"
	case FavoriteAnime:
		return "an anime"
	case FavoriteManga:
		return "a manga"
	case FavoriteBook:
		return "a book"
	default:
		return "an album"
	}
}

// Favorites are a user's favorites, every kind in order, with the titles they name.
type Favorites map[FavoriteKind][]core.Title

// Favorites reads a user's favorites.
func (s *Service) Favorites(ctx context.Context, user uuid.UUID) (Favorites, error) {
	ids, err := s.Store.FavoriteIDs(ctx, user)
	if err != nil {
		return nil, err
	}
	var all []uuid.UUID
	for _, list := range ids {
		all = append(all, list...)
	}
	out := Favorites{}
	if len(all) == 0 {
		return out, nil
	}
	titles, err := s.titles(ctx, all)
	if err != nil {
		return nil, err
	}
	for kind, list := range ids {
		row := []core.Title{}
		for _, id := range list {
			if t, ok := titles[id]; ok {
				row = append(row, t)
			}
		}
		out[kind] = row
	}
	return out, nil
}

// ReplaceFavorites replaces one kind: adding, removing and reordering are all this one write.
func (s *Service) ReplaceFavorites(ctx context.Context, kind FavoriteKind, refs []core.MediaRef, user uuid.UUID) (Favorites, error) {
	if len(refs) > FavoriteLimit {
		return nil, invalid("items", fmt.Sprintf("A top 10 holds at most %d titles.", FavoriteLimit))
	}
	titles := make([]core.Title, 0, len(refs))
	for _, ref := range refs {
		t, err := s.resolveTitle(ctx, ref)
		if err != nil {
			return nil, err
		}
		titles = append(titles, t)
	}
	for _, t := range titles {
		if KindOf(t) != kind {
			return nil, invalid("items", fmt.Sprintf("%s is not %s.", t.Title, article(kind)))
		}
	}
	ids := make([]uuid.UUID, 0, len(titles))
	seen := map[uuid.UUID]bool{}
	for _, t := range titles {
		if seen[t.ID] {
			return nil, invalid("items", "Each title can be in the top 10 once.")
		}
		seen[t.ID] = true
		ids = append(ids, t.ID)
	}
	if err := s.Store.ReplaceFavorites(ctx, ids, kind, user); err != nil {
		return nil, err
	}
	return s.Favorites(ctx, user)
}
