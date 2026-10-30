package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/testdb"
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// MusicBrainz (MUS-001), albums in the catalog, ListenBrainz rows (MUS-002).

func musicBrainz(stub *stubTransport) *MusicBrainz {
	return &MusicBrainz{Client: testClient(stub, "musicbrainz"), UserAgent: "Aaru-test"}
}

func TestMusicBrainzSearch(t *testing.T) {
	stub := routes(map[string]string{"/release-group": `{"release-groups":[
	  {"id":"b1392450-e666-3926-a536-22c65f834433","title":"OK Computer","primary-type":"Album",
	   "first-release-date":"1997-05-21","artist-credit":[{"name":"Radiohead","joinphrase":""}]},
	  {"id":"single-1","title":"Paranoid Android","primary-type":"Single","first-release-date":"1997-05-26",
	   "artist-credit":[{"name":"Radiohead"}]},
	  {"id":"ep-1","title":"Duet EP","primary-type":"EP","first-release-date":"2001",
	   "artist-credit":[{"name":"Simon","joinphrase":" & "},{"name":"Garfunkel"}]}]}`})
	hits, err := musicBrainz(stub).Search(context.Background(), "ok computer (live)", core.MediaAlbum)
	require.NoError(t, err)
	assert.Equal(t, []string{"OK Computer", "Duet EP"}, titlesOf(hits), "singles are not tracked")
	album := hits[0]
	assert.Equal(t, core.MediaAlbum, album.Type)
	assert.Equal(t, 1997, *album.Year)
	assert.Equal(t, "1997-05-21", *album.ReleaseDate)
	assert.Equal(t, "Radiohead", *album.Byline)
	assert.Equal(t, core.ExternalIDs{MusicBrainz: "b1392450-e666-3926-a536-22c65f834433"}, album.IDs)
	assert.Equal(t, "https://coverartarchive.org/release-group/b1392450-e666-3926-a536-22c65f834433/front-250", *album.PosterURL)
	assert.Equal(t, "Simon & Garfunkel", *hits[1].Byline)
	req := stub.first(t)
	q := urlQuery(req.URL)
	assert.Equal(t, "json", q.Get("fmt"))
	assert.Contains(t, q.Get("query"), `ok computer \(live\)`, "the user's punctuation is escaped, never syntax")
	assert.True(t, hasHeader(req, "User-Agent", "Aaru-test"))
}

func TestMusicBrainzHydrate(t *testing.T) {
	stub := routes(map[string]string{"/release-group/rg-1": `{"id":"rg-1","title":"Kid A","primary-type":"Album","first-release-date":"2000-10-02",
	 "artist-credit":[{"name":"Radiohead"}],
	 "genres":[{"name":"electronic","count":9},{"name":"art rock","count":12},{"name":"ambient","count":3},
	           {"name":"experimental","count":7},{"name":"idm","count":2},{"name":"glitch","count":1}]}`})
	ctx := context.Background()
	title, err := musicBrainz(stub).Hydrate(ctx, core.ExternalIDs{MusicBrainz: "rg-1"}, core.MediaAlbum)
	require.NoError(t, err)
	require.NotNil(t, title)
	assert.Equal(t, []string{"art rock", "electronic", "experimental", "ambient", "idm"}, title.Genres)
	assert.Equal(t, "Radiohead", *title.Hit.Byline)
	missing, err := musicBrainz(stub).Hydrate(ctx, core.ExternalIDs{MusicBrainz: "rg-404"}, core.MediaAlbum)
	require.NoError(t, err)
	assert.Nil(t, missing)
	other, err := musicBrainz(stub).Hydrate(ctx, core.ExternalIDs{TMDB: "603"}, core.MediaAlbum)
	require.NoError(t, err)
	assert.Nil(t, other)
}

func TestMusicBrainzTracksFromTheEarliestRelease(t *testing.T) {
	stub := routes(map[string]string{"/release": `{"releases":[
	  {"date":"2009-03-24","media":[{"position":1,"tracks":[{"position":1,"title":"Remaster Intro","length":1000}]}]},
	  {"media":[{"position":1,"tracks":[{"position":1,"title":"Undated","length":1}]}]},
	  {"date":"1997-05-21","media":[
	    {"position":1,"tracks":[{"position":1,"title":"Airbag","length":284000},{"position":2,"title":"Paranoid Android","length":383000}]},
	    {"position":2,"tracks":[{"position":1,"title":"Bonus","length":null}]}]}]}`})
	tracks, err := musicBrainz(stub).Tracks(context.Background(), core.ExternalIDs{MusicBrainz: "rg-1"})
	require.NoError(t, err)
	assert.Equal(t, []AlbumTrack{
		{Disc: 1, Position: 1, Name: "Airbag", LengthMs: ptr(284_000)},
		{Disc: 1, Position: 2, Name: "Paranoid Android", LengthMs: ptr(383_000)},
		{Disc: 2, Position: 1, Name: "Bonus"},
	}, tracks)
	q := urlQuery(stub.first(t).URL)
	assert.Equal(t, "rg-1", q.Get("release-group"))
	assert.Equal(t, "official", q.Get("status"))
}

func TestMusicBrainzMatchRecording(t *testing.T) {
	recordings := []MusicBrainzRecording{}
	stub := routes(map[string]string{"/recording": `{"recordings":[
	  {"id":"rec-1","score":100,"title":"Airbag","artist-credit":[{"name":"Radiohead","artist":{"id":"art-1"}}],
	   "releases":[{"title":"OK Computer","release-group":{"id":"rg-1","title":"OK Computer","primary-type":"Album"}},
	               {"title":"Airbag / How Am I Driving?","release-group":{"id":"rg-2","primary-type":"EP"}}]},
	  {"id":"rec-2","score":80,"title":"Airbag (live)","artist-credit":[{"name":"Radiohead"}]}]}`})
	match, err := musicBrainz(stub).Match(context.Background(), RecordingQuery{Artist: "radiohead", Track: "AIRBAG", Album: ptr("ok computer")})
	require.NoError(t, err)
	assert.Equal(t, "rec-1", *match.RecordingMBID)
	assert.Equal(t, "rg-1", *match.ReleaseGroupMBID)
	assert.Equal(t, "art-1", *match.ArtistMBID)
	assert.Contains(t, urlQuery(stub.first(t).URL).Get("query"), `recording:"AIRBAG" AND artist:"radiohead"`)
	// With no album sent, two albums or EPs is no answer.
	assert.Nil(t, MatchRecording(RecordingQuery{Artist: "Radiohead", Track: "Airbag"}, decodeRecordings(t, stub)).ReleaseGroupMBID)
	assert.Equal(t, RecordingMatch{}, MatchRecording(RecordingQuery{Artist: "x", Track: "y"}, recordings))
	assert.Equal(t, "a b", FoldName("  Ａ\tB "))
}

func decodeRecordings(t *testing.T, stub *stubTransport) []MusicBrainzRecording {
	t.Helper()
	var page struct {
		Recordings []MusicBrainzRecording `json:"recordings"`
	}
	require.NoError(t, (&MusicBrainz{Client: testClient(stub, "musicbrainz")}).get(context.Background(), "recording", nil, &page))
	return page.Recordings
}

func albumRecord(name, mbid string) Record {
	return Record{Hit: Hit{
		Type: core.MediaAlbum, Title: name, Year: ptr(1997), PosterURL: MusicBrainzCoverURL(mbid),
		Byline: ptr("Radiohead"), IDs: core.ExternalIDs{MusicBrainz: mbid},
	}, Genres: []string{"art rock", "alternative rock"}}
}

func TestAlbumDetailCarriesArtistGenresAndTracks(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	fake := newFake()
	fake.stubTitle(albumRecord("OK Computer", "mb-1"))
	fake.stubTracks("mb-1", []AlbumTrack{{Disc: 1, Position: 1, Name: "Airbag", LengthMs: ptr(284_000)}, {Disc: 1, Position: 2, Name: "Paranoid Android"}})
	title, err := NewResolver(store, fake.providers()).Resolve(ctx, core.MediaRef{Type: core.MediaAlbum, IDs: core.ExternalIDs{MusicBrainz: "mb-1"}}, nil)
	require.NoError(t, err)
	assert.Equal(t, "Radiohead", *title.Byline)
	service := NewService(store, fake.providers())
	detail, err := service.Detail(ctx, title.ID)
	require.NoError(t, err)
	assert.Equal(t, []string{"art rock", "alternative rock"}, detail.Genres)
	require.Len(t, detail.Tracks, 2)
	assert.Equal(t, "Airbag", detail.Tracks[0].Name)
	assert.Equal(t, 284_000, *detail.Tracks[0].LengthMs)
	assert.Nil(t, detail.Episodes)
	_, err = service.Detail(ctx, title.ID)
	require.NoError(t, err)
	assert.Equal(t, 1, fake.callCount("tracks"), "a stored tracklist is not fetched again")
}

func TestAlbumDetailWithoutMusicBrainz(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	fake := newFake()
	fake.stubTitle(albumRecord("Kid A", "mb-2"))
	title, err := NewResolver(store, fake.providers()).Resolve(ctx, core.MediaRef{Type: core.MediaAlbum, IDs: core.ExternalIDs{MusicBrainz: "mb-2"}}, nil)
	require.NoError(t, err)
	fake.fail(provider.NewError("musicbrainz", provider.KindUnavailable))
	detail, err := NewService(store, fake.providers()).Detail(ctx, title.ID)
	require.NoError(t, err)
	assert.Nil(t, detail.Tracks, "no tracklist yet, rather than an empty one")
}

func TestAlbumSearchIsMusicBrainzAlone(t *testing.T) {
	fake := newFake()
	fake.stubSearch("radiohead", []Hit{albumRecord("OK Computer", "mb-3").Hit})
	result, err := NewService(nil, fake.providers()).Search(context.Background(), "radiohead", ScopeAlbum)
	require.NoError(t, err)
	require.Len(t, result.Hits, 1)
	assert.Equal(t, core.MediaAlbum, result.Hits[0].Type)
	assert.False(t, result.Incomplete)
	noMusic, err := NewService(nil, Providers{}).Search(context.Background(), "radiohead", ScopeAlbum)
	require.NoError(t, err)
	assert.True(t, noMusic.Incomplete)
}

// MARK: ListenBrainz

func lbRelease(group, name, date string, kind *string, secondary *string, artists []string, cover bool) string {
	mbids := []string{}
	for _, a := range artists {
		mbids = append(mbids, `"`+a+`"`)
	}
	caa := `"caa_id":null,"caa_release_mbid":null`
	if cover {
		caa = `"caa_id":123,"caa_release_mbid":"rel-` + group + `"`
	}
	quoted := func(s *string) string {
		if s == nil {
			return "null"
		}
		return `"` + *s + `"`
	}
	return fmt.Sprintf(`{"artist_credit_name":"Artist %s","artist_mbids":[%s],%s,"listen_count":0,
	 "release_date":"%s","release_group_mbid":"%s","release_mbid":"rel-%s",
	 "release_group_primary_type":%s,"release_group_secondary_type":%s,"release_name":"%s"}`,
		name, strings.Join(mbids, ","), caa, date, group, group, quoted(kind), quoted(secondary), name)
}

func listenBrainzStub(past, future []string, groups, artists string) *stubTransport {
	return stubFunc(func(req provider.Request) provider.Response {
		path := urlPath(req.URL)
		var body string
		switch {
		case strings.HasSuffix(strings.TrimSuffix(path, "/"), "explore/fresh-releases"):
			list := future
			if urlQuery(req.URL).Get("past") == "true" {
				list = past
			}
			body = fmt.Sprintf(`{"payload":{"releases":[%s],"total_count":%d}}`, strings.Join(list, ","), len(list))
		case strings.HasSuffix(path, "stats/sitewide/release-groups"):
			body = `{"payload":{"release_groups":` + groups + `}}`
		case strings.HasSuffix(path, "stats/sitewide/artists"):
			body = `{"payload":{"artists":` + artists + `}}`
		default:
			return provider.Response{Status: 404}
		}
		return provider.Response{Status: 200, Body: []byte(body)}
	})
}

func TestListenBrainzNewAlbums(t *testing.T) {
	album := ptr("Album")
	stub := listenBrainzStub([]string{
		lbRelease("rg-a", "Dopamine Chamber", "2026-10-15", album, nil, nil, true),
		lbRelease("rg-b", "Popstar", "2026-09-25", ptr("EP"), nil, nil, true),
		lbRelease("rg-c", "A Single", "2026-10-10", ptr("Single"), nil, nil, true),
		lbRelease("rg-d", "Live at Home", "2026-10-10", album, ptr("Live"), nil, true),
		lbRelease("rg-e", "No Cover", "2026-10-10", album, nil, nil, false),
		lbRelease("rg-f", "Unplayed", "2026-10-12", album, nil, nil, true),
	}, nil, `[{"release_group_mbid":"old-hit","listen_count":9000},{"release_group_mbid":"rg-b","listen_count":987},
	 {"release_group_mbid":"rg-a","listen_count":2901},{"release_group_mbid":"rg-c","listen_count":5000},
	 {"release_group_mbid":"rg-d","listen_count":4000},{"release_group_mbid":"rg-e","listen_count":3000},
	 {"release_group_mbid":null,"listen_count":100}]`, "[]")
	source := &ListenBrainz{Client: testClient(stub, "listenbrainz"), UserAgent: "Aaru-test"}
	hits, err := source.List(context.Background(), ListMusicNew, time.Now())
	require.NoError(t, err)
	assert.Equal(t, []string{"Dopamine Chamber", "Popstar"}, titlesOf(hits))
	first := hits[0]
	assert.Equal(t, core.MediaAlbum, first.Type)
	assert.Equal(t, core.ExternalIDs{MusicBrainz: "rg-a"}, first.IDs)
	assert.Equal(t, "Artist Dopamine Chamber", *first.Byline)
	assert.Equal(t, 2026, *first.Year)
	assert.Equal(t, "2026-10-15", *first.ReleaseDate)
	assert.Equal(t, "https://coverartarchive.org/release/rel-rg-a/123-250.jpg", *first.PosterURL)
	for _, r := range stub.all() {
		assert.True(t, hasHeader(r, "User-Agent", "Aaru-test"))
	}
}

func TestListenBrainzComingSoon(t *testing.T) {
	album := ptr("Album")
	stub := listenBrainzStub(nil, []string{
		lbRelease("rg-late", "Late", "2026-11-13", album, nil, []string{"u2"}, true),
		lbRelease("rg-soon", "Soon", "2026-10-23", album, nil, []string{"paak", "cordae"}, true),
		lbRelease("rg-va", "Compiled", "2026-10-22", album, nil, []string{ListenBrainzVariousArtists}, true),
		lbRelease("rg-nobody", "Nobody", "2026-10-22", album, nil, []string{"unknown"}, true),
		lbRelease("rg-tie", "Tie", "2026-10-23", album, nil, []string{"qotsa"}, true),
		lbRelease("rg-single", "Single", "2026-10-22", ptr("Single"), nil, []string{"u2"}, true),
	}, "[]", `[{"artist_mbid":"qotsa","listen_count":900},{"artist_mbid":"`+ListenBrainzVariousArtists+`","listen_count":800},
	 {"artist_mbid":"u2","listen_count":700},{"artist_mbid":"cordae","listen_count":600},{"artist_mbid":null,"listen_count":500}]`)
	hits, err := (&ListenBrainz{Client: testClient(stub, "listenbrainz")}).List(context.Background(), ListMusicUpcoming, time.Now())
	require.NoError(t, err)
	// Same day: the more played artist first (qotsa ranks above cordae).
	assert.Equal(t, []string{"Tie", "Soon", "Late"}, titlesOf(hits))
}

func TestListenBrainzOtherListIsNotFound(t *testing.T) {
	source := &ListenBrainz{Client: testClient(listenBrainzStub(nil, nil, "[]", "[]"), "listenbrainz")}
	_, err := source.List(context.Background(), ListBooksTrending, time.Now())
	assert.True(t, provider.IsNotFound(err))
	assert.Equal(t, []DiscoverList{ListMusicNew, ListMusicUpcoming}, source.DiscoverLists())
}
