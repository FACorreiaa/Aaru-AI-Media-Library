package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/social"
	"context"
)

// FavoriteHandlers.swift: FAV-001, a top 10 per kind, set in Settings and shown on the profile.

// GetMyFavorites answers the viewer's favorites.
func (s *Server) GetMyFavorites(ctx context.Context, _ api.GetMyFavoritesRequestObject) (api.GetMyFavoritesResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	favorites, err := s.Social.Favorites(ctx, viewer)
	if err != nil {
		return nil, err
	}
	return api.GetMyFavorites200JSONResponse(FavoritesDTO(favorites)), nil
}

// SetMyFavorites replaces one kind.
func (s *Server) SetMyFavorites(ctx context.Context, req api.SetMyFavoritesRequestObject) (api.SetMyFavoritesResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	kind := social.FavoriteKind(req.Kind)
	if req.Body == nil || !kind.Valid() {
		return nil, apperr.BadRequest()
	}
	refs := make([]core.MediaRef, 0, len(req.Body.Items))
	for _, ref := range req.Body.Items {
		refs = append(refs, MediaRefFromAPI(ref))
	}
	saved, err := s.Social.ReplaceFavorites(ctx, kind, refs, viewer)
	if err != nil {
		return nil, err
	}
	return api.SetMyFavorites200JSONResponse(FavoritesDTO(saved)), nil
}

// FavoritesDTO is every kind's row on the wire, empty kinds included.
func FavoritesDTO(f social.Favorites) api.Favorites {
	row := func(kind social.FavoriteKind) []api.TitleSummary {
		out := make([]api.TitleSummary, 0, len(f[kind]))
		for _, t := range f[kind] {
			out = append(out, TitleSummaryDTO(t))
		}
		return out
	}
	return api.Favorites{
		Film: row(social.FavoriteFilm), Show: row(social.FavoriteShow), Anime: row(social.FavoriteAnime),
		Manga: row(social.FavoriteManga), Book: row(social.FavoriteBook), Album: row(social.FavoriteAlbum),
	}
}
