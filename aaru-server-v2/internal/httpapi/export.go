package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/export"
	"context"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"
	"golang.org/x/sync/errgroup"
)

// ExportAccount is `GET /v1/me/export` (ExportHandlers.swift): the whole account as JSON, or
// the library as a CSV Aaru's generic importer reads back.
func (s *Server) ExportAccount(ctx context.Context, req api.ExportAccountRequestObject) (api.ExportAccountResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	me, err := s.me(ctx, userID)
	if err != nil {
		return nil, err
	}
	svc := s.exportService()
	account, err := svc.Gather(ctx, userID)
	if err != nil {
		return nil, err
	}
	now := time.Now()
	stamp := now.UTC().Format(time.DateOnly)
	if req.Params.Format != nil && *req.Params.Format == api.ExportAccountParamsFormatCsv {
		body := account.CSV()
		disposition := fmt.Sprintf("attachment; filename=\"aaru-library-%s.csv\"", stamp)
		return api.ExportAccount200TextcsvResponse{
			Body: strings.NewReader(body), ContentLength: int64(len(body)),
			Headers: api.ExportAccount200ResponseHeaders{ContentDisposition: &disposition},
		}, nil
	}

	library := make([]api.LibraryEntry, 0, len(account.Entries))
	for _, e := range account.Entries {
		dto := LibraryEntryDTO(e)
		if keys, ok := account.Watched[e.Item.ID]; ok && len(keys) > 0 {
			refs := EpisodeRefsDTO(keys)
			dto.WatchedEpisodes = &refs
		}
		library = append(library, dto)
	}
	out := api.AccountExport{
		ExportedAt: apitime.From(now),
		Account:    me,
		Library:    library,
		Lists: make([]struct {
			CreatedAt apitime.Time       `json:"createdAt"`
			Items     []api.TitleSummary `json:"items"`
			Name      string             `json:"name"`
		}, 0, len(account.Lists)),
		Shelves: make([]api.Shelf, 0, len(account.Shelves)),
	}
	for _, l := range account.Lists {
		items := make([]api.TitleSummary, 0, len(l.Titles))
		for _, t := range l.Titles {
			items = append(items, TitleSummaryDTO(t))
		}
		out.Lists = append(out.Lists, struct {
			CreatedAt apitime.Time       `json:"createdAt"`
			Items     []api.TitleSummary `json:"items"`
			Name      string             `json:"name"`
		}{CreatedAt: apitime.From(l.CreatedAt), Items: items, Name: l.Name})
	}
	for _, sh := range account.Shelves {
		out.Shelves = append(out.Shelves, shelfDTO(sh))
	}
	if err := s.exportExtras(ctx, svc, userID, &out); err != nil {
		return nil, err
	}
	disposition := fmt.Sprintf("attachment; filename=\"aaru-export-%s.json\"", stamp)
	return api.ExportAccount200JSONResponse{
		Body: out, Headers: api.ExportAccount200ResponseHeaders{ContentDisposition: &disposition},
	}, nil
}

func (s *Server) exportService() *export.Service {
	return &export.Service{Pool: s.Pool, Q: s.q}
}

// exportExtras reads the account's social, group, music, favorite and sports data, each
// independently.
func (s *Server) exportExtras(ctx context.Context, svc *export.Service, userID uuid.UUID, out *api.AccountExport) error {
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		rows, err := s.q.ExportFriends(gctx, userID)
		if err != nil {
			return fmt.Errorf("export friends: %w", err)
		}
		users := make([]api.SocialUser, 0, len(rows))
		for _, r := range rows {
			users = append(users, exportSocialUser(r.UserID, r.Handle, r.DisplayName, r.AvatarVersion))
		}
		out.Friends = &users
		return nil
	})
	g.Go(func() error {
		rows, err := s.q.ExportBlocked(gctx, userID)
		if err != nil {
			return fmt.Errorf("export blocked: %w", err)
		}
		users := make([]api.SocialUser, 0, len(rows))
		for _, r := range rows {
			users = append(users, exportSocialUser(r.UserID, r.Handle, r.DisplayName, r.AvatarVersion))
		}
		out.Blocked = &users
		return nil
	})
	g.Go(func() error {
		rows, err := s.q.ExportGroups(gctx, userID)
		if err != nil {
			return fmt.Errorf("export groups: %w", err)
		}
		groups := make([]struct {
			Name string        `json:"name"`
			Role api.GroupRole `json:"role"`
		}, 0, len(rows))
		for _, r := range rows {
			role := api.GroupRole(r.Role)
			if !role.Valid() {
				return fmt.Errorf("export groups: unknown role %q", r.Role)
			}
			groups = append(groups, struct {
				Name string        `json:"name"`
				Role api.GroupRole `json:"role"`
			}{Name: r.Name, Role: role})
		}
		out.Groups = &groups
		return nil
	})
	g.Go(func() error {
		rows, err := s.q.ExportGroupMessages(gctx, &userID)
		if err != nil {
			return fmt.Errorf("export group messages: %w", err)
		}
		messages := make([]struct {
			Body      string       `json:"body"`
			Channel   string       `json:"channel"`
			CreatedAt apitime.Time `json:"createdAt"`
			Group     string       `json:"group"`
		}, 0, len(rows))
		for _, r := range rows {
			messages = append(messages, struct {
				Body      string       `json:"body"`
				Channel   string       `json:"channel"`
				CreatedAt apitime.Time `json:"createdAt"`
				Group     string       `json:"group"`
			}{Body: r.Body, Channel: r.ChannelName, CreatedAt: apitime.From(r.CreatedAt), Group: r.GroupName})
		}
		out.GroupMessages = &messages
		return nil
	})
	g.Go(func() error {
		rows, err := s.q.ExportListens(gctx, userID)
		if err != nil {
			return fmt.Errorf("export listens: %w", err)
		}
		listens := make([]api.Listen, 0, len(rows))
		for _, r := range rows {
			listens = append(listens, exportListen(r))
		}
		out.Listens = &listens
		return nil
	})
	g.Go(func() error {
		byKind, err := svc.Favorites(gctx, userID)
		if err != nil {
			return err
		}
		row := func(kind string) []api.TitleSummary {
			items := make([]api.TitleSummary, 0, len(byKind[kind]))
			for _, t := range byKind[kind] {
				items = append(items, TitleSummaryDTO(t))
			}
			return items
		}
		out.Favorites = &api.Favorites{
			Film: row("film"), Show: row("show"), Anime: row("anime"), Manga: row("manga"), Book: row("book"),
			Album: row("album"),
		}
		return nil
	})
	g.Go(func() error {
		follows, err := s.Sports.Follows(gctx, userID)
		if err != nil {
			return err
		}
		country, err := s.Sports.WatchCountry(gctx, userID)
		if err != nil {
			return err
		}
		entities := make([]api.SportEntity, 0, len(follows))
		for _, f := range follows {
			entities = append(entities, sportEntityDTO(f, map[string]bool{sportFollowKey(f): true}))
		}
		out.Sports = &api.SportsExport{Follows: entities, WatchCountryCode: country}
		return nil
	})
	g.Go(func() error {
		avatar, err := svc.Avatar(gctx, userID)
		if err != nil {
			return err
		}
		if avatar != nil {
			out.AvatarJpeg = &avatar
		}
		return nil
	})
	return g.Wait()
}

func exportSocialUser(id uuid.UUID, handle string, displayName *string, avatarVersion *int64) api.SocialUser {
	u := api.SocialUser{UserId: apiid.From(id), Handle: handle, DisplayName: displayName}
	if avatarVersion != nil {
		path := AvatarPath(id, *avatarVersion)
		u.AvatarUrl = &path
	}
	return u
}

// exportListen is Components.Schemas.Listen(Listen). Its id is lowercase, as Swift wrote it.
// TODO: fold into listen.go after merge with the listens area.
func exportListen(r sqlc.ExportListensRow) api.Listen {
	l := api.Listen{
		Id: strings.ToLower(r.ID.String()), ListenedAt: apitime.From(r.ListenedAt), Artist: r.Artist, Track: r.Track,
		Album: r.Album, OriginUrl: r.OriginUrl, Client: r.Client, MusicService: r.MusicService,
	}
	if r.DurationMs != nil {
		ms := int(*r.DurationMs)
		l.DurationMs = &ms
	}
	if mbid := r.ReleaseGroupMbid; mbid != nil {
		if cover := catalog.MusicBrainzCoverURL(*mbid); validURL(*cover) {
			l.CoverUrl = cover
		}
		mb := *mbid
		ref := api.MediaRef{
			Type: api.MediaType(core.MediaAlbum), Ids: &api.ExternalIds{Musicbrainz: &mb}, Title: r.Album,
			TitleId: apiid.PtrOrNil(r.AlbumTitleID),
		}
		l.AlbumRef = &ref
	}
	return l
}

// validURL is Foundation's URL(string:) refusing a string with spaces or other bare characters.
func validURL(s string) bool {
	if strings.ContainsAny(s, " \t\n\r\"<>\\^`{|}") {
		return false
	}
	_, err := url.Parse(s)
	return err == nil
}

// shelfDTO is Components.Schemas.Shelf(Shelf).
// TODO: fold into list.go after merge with the lists area.
func shelfDTO(sh export.Shelf) api.Shelf {
	f := sh.Filter
	out := api.Shelf{
		Id: apiid.From(sh.ID), Name: sh.Name, IsPinned: sh.IsPinned,
		Filter: api.ShelfFilter{Anime: f.IsAnime, Owned: f.IsOwned, List: apiid.PtrOrNil(f.ListID)},
	}
	if f.Type != nil {
		t := api.MediaType(*f.Type)
		out.Filter.Type = &t
	}
	if f.Status != nil {
		st := api.LibraryStatus(*f.Status)
		out.Filter.Status = &st
	}
	return out
}
