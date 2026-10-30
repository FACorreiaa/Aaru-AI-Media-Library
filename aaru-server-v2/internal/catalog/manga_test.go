package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/testdb"
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// AniList's manga (MNG-001) against canned JSON.

func aniListWith(body string) (*AniList, *stubTransport) {
	stub := constant(body)
	return &AniList{Client: testClient(stub, "anilist"), UserAgent: "Aaru-test"}, stub
}

func TestMangaSearchCreditsTheAuthors(t *testing.T) {
	anilist, stub := aniListWith(`{"data":{"Page":{"media":[
	  {"id":30013,"idMal":13,"type":"MANGA","format":"MANGA","status":"RELEASING","chapters":null,"volumes":null,
	   "title":{"romaji":"ONE PIECE","english":"One Piece","native":"ONE PIECE"},
	   "startDate":{"year":1997},"coverImage":{"large":"https://img/op.jpg"},"description":"Pirates.",
	   "staff":{"edges":[{"role":"Story & Art","node":{"name":{"full":"Eiichiro Oda"}}},
	                     {"role":"Translator (English)","node":{"name":{"full":"Stephen Paul"}}}]}},
	  {"id":30002,"idMal":2,"type":"MANGA","format":"MANGA","status":"FINISHED","chapters":364,"volumes":41,
	   "title":{"romaji":"Berserk","english":null,"native":"ベルセルク"},"startDate":{"year":1989},
	   "staff":{"edges":[{"role":"Story","node":{"name":{"full":"Kentarou Miura"}}},
	                     {"role":"Art","node":{"name":{"full":"Kouji Mori"}}},
	                     {"role":"Art","node":{"name":{"full":"Kentarou Miura"}}}]}}]}}}`)
	hits, err := anilist.Search(context.Background(), "x", core.MediaManga)
	require.NoError(t, err)
	require.Len(t, hits, 2)
	for _, h := range hits {
		assert.Equal(t, core.MediaManga, h.Type)
		assert.False(t, h.IsAnime)
		assert.Nil(t, h.Network)
	}
	assert.Equal(t, core.ExternalIDs{AniList: "30013", MAL: "13"}, hits[0].IDs)
	assert.Equal(t, "Eiichiro Oda", *hits[0].Byline, "translators are not authors")
	assert.Nil(t, hits[0].ChapterCount, "a running series has no count yet")
	assert.Equal(t, "Kentarou Miura, Kouji Mori", *hits[1].Byline)
	assert.Equal(t, 364, *hits[1].ChapterCount)
	assert.Equal(t, 41, *hits[1].VolumeCount)
	body := string(stub.first(t).Body)
	assert.Contains(t, body, "type: MANGA, isAdult: false")
	assert.Contains(t, body, "staff(")
}

func TestAnimeSearchAsksNoCredits(t *testing.T) {
	anilist, stub := aniListWith(`{"data":{"Page":{"media":[]}}}`)
	_, err := anilist.Search(context.Background(), "x", core.MediaShow)
	require.NoError(t, err)
	body := string(stub.first(t).Body)
	assert.Contains(t, body, "type: ANIME")
	assert.NotContains(t, body, "staff(")
}

func TestMALBatchesAskForTheListsType(t *testing.T) {
	anilist, stub := aniListWith(`{"data":{"Page":{"media":[{"id":30002,"idMal":2,"type":"MANGA","format":"MANGA",
	  "title":{"romaji":"Berserk"},"startDate":{"year":1989}}]}}}`)
	found, err := anilist.HydrateMAL(context.Background(), []string{"2"}, core.MediaManga)
	require.NoError(t, err)
	assert.Equal(t, core.MediaManga, found["2"].Hit.Type)
	assert.Contains(t, string(stub.first(t).Body), "idMal_in: $ids, type: MANGA")
}

func mangaRecord(name, anilist, mal string) Record {
	return Record{
		Hit: Hit{
			Type: core.MediaManga, Title: name, Year: ptr(1989), Byline: ptr("Kentarou Miura"),
			IDs: core.ExternalIDs{AniList: anilist, MAL: mal}, ChapterCount: ptr(364), VolumeCount: ptr(41),
		},
		Status: ptr(StatusEnded), Genres: []string{"Action"},
	}
}

func TestMangaResolvesWithAuthorAndCounts(t *testing.T) {
	fake := newFake()
	fake.stubTitle(mangaRecord("Berserk", "30002", ""))
	title, err := NewResolver(NewStore(testdb.New(t)), fake.providers()).Resolve(context.Background(),
		core.MediaRef{Type: core.MediaManga, IDs: core.ExternalIDs{AniList: "30002"}}, nil)
	require.NoError(t, err)
	assert.Equal(t, core.MediaManga, title.Type)
	assert.False(t, title.IsAnime)
	assert.Equal(t, "Kentarou Miura", *title.Byline)
	assert.Equal(t, 364, *title.ChapterCount)
	assert.Equal(t, 41, *title.VolumeCount)
}

func TestAnimeAndMangaWithOneMALNumberAreTwoTitles(t *testing.T) {
	ctx := context.Background()
	fake := newFake()
	fake.stubTitle(Record{
		Hit:    Hit{Type: core.MediaShow, Title: "Some Anime", Year: ptr(2001), IDs: core.ExternalIDs{AniList: "1", MAL: "4242"}, IsAnime: true},
		Status: ptr(StatusEnded), RuntimeMinutes: ptr(24),
	})
	fake.stubTitle(mangaRecord("Some Manga", "2", "4242"))
	resolver := NewResolver(NewStore(testdb.New(t)), fake.providers())
	anime, err := resolver.Resolve(ctx, core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{MAL: "4242"}}, nil)
	require.NoError(t, err)
	manga, err := resolver.Resolve(ctx, core.MediaRef{Type: core.MediaManga, IDs: core.ExternalIDs{MAL: "4242"}}, nil)
	require.NoError(t, err)
	assert.Equal(t, "Some Anime", anime.Title)
	assert.Equal(t, "Some Manga", manga.Title)
	assert.NotEqual(t, anime.ID, manga.ID)

	// The same through a prefetched run (IMP-017).
	prefetched, err := NewResolver(NewStore(testdb.New(t)), fake.providers()).PrefetchingMAL(ctx, []core.MediaRef{
		{Type: core.MediaShow, IDs: core.ExternalIDs{MAL: "4242"}},
		{Type: core.MediaManga, IDs: core.ExternalIDs{MAL: "4242"}},
		{Type: core.MediaShow, IDs: core.ExternalIDs{MAL: "999"}},
	})
	require.NoError(t, err)
	assert.Equal(t, 2, fake.callCount("hydrateMAL"))
	hydrates := fake.callCount("hydrate")
	a, err := prefetched.Resolve(ctx, core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{MAL: "4242"}}, nil)
	require.NoError(t, err)
	m, err := prefetched.Resolve(ctx, core.MediaRef{Type: core.MediaManga, IDs: core.ExternalIDs{MAL: "4242"}}, nil)
	require.NoError(t, err)
	assert.Equal(t, "Some Anime", a.Title)
	assert.Equal(t, "Some Manga", m.Title)
	_, err = prefetched.Resolve(ctx, core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{MAL: "999"}}, nil)
	assert.ErrorIs(t, err, ErrUnresolvable, "asked once, unknown")
	assert.Equal(t, hydrates, fake.callCount("hydrate"), "the prefetch answered every ref")

	down := prefetched.WithoutAniList(provider.NewError("anilist", provider.KindUnavailable))
	_, err = down.Resolve(ctx, core.MediaRef{Type: core.MediaManga, IDs: core.ExternalIDs{AniList: "77"}}, nil)
	assert.True(t, provider.IsAniListOutage(err))
}

func TestMangaSearchSaysWhenAniListIsDown(t *testing.T) {
	fake := newFake()
	fake.stubSearch("berserk", []Hit{mangaRecord("Berserk", "30002", "").Hit})
	service := NewService(nil, fake.providers())
	found, err := service.Search(context.Background(), "berserk", ScopeManga)
	require.NoError(t, err)
	require.Len(t, found.Hits, 1)
	assert.Equal(t, core.MediaManga, found.Hits[0].Type)
	assert.False(t, found.Incomplete)
	fake.fail(provider.NewError("anilist", provider.KindUnavailable))
	down, err := service.Search(context.Background(), "berserk", ScopeManga)
	require.NoError(t, err)
	assert.Empty(t, down.Hits)
	assert.True(t, down.Incomplete)
	assert.Equal(t, NoticeMangaDown, *down.Notice)
}

func TestEpisodeNameMatcher(t *testing.T) {
	episodes := []Episode{
		{Season: 0, Episode: 1, Name: ptr("The Special")},
		{Season: 1, Episode: 1, Name: ptr("Pilot")},
		{Season: 2, Episode: 3, Name: ptr("Reunion")},
		{Season: 3, Episode: 1, Name: ptr("Reunion")},
	}
	key, ok := MatchEpisodeName(NamedEpisode{Season: ptr(4), Name: "pilot"}, episodes)
	require.True(t, ok, "the one episode in the show with that name")
	assert.Equal(t, core.EpisodeKey{Season: 1, Episode: 1}, key)
	key, ok = MatchEpisodeName(NamedEpisode{Season: ptr(3), Name: "Reunion"}, episodes)
	require.True(t, ok)
	assert.Equal(t, core.EpisodeKey{Season: 3, Episode: 1}, key)
	_, ok = MatchEpisodeName(NamedEpisode{Name: "Reunion"}, episodes)
	assert.False(t, ok, "two with the name is no answer")
	_, ok = MatchEpisodeName(NamedEpisode{Name: "The Special"}, episodes)
	assert.False(t, ok, "specials only match season 0")
	_, ok = MatchEpisodeName(NamedEpisode{Season: ptr(0), Name: "The Special"}, episodes)
	assert.True(t, ok)
}
