package app

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/concerts"
	"context"
)

// concertArtists lets the concert refresher read album artists from MusicBrainz
// (MUS-003), sharing the catalog's one-call-a-second pacer.
type concertArtists struct{ mb *catalog.MusicBrainz }

func (a concertArtists) AlbumArtists(ctx context.Context, releaseGroupMBID string) ([]concerts.MusicArtist, error) {
	artists, err := a.mb.Artists(ctx, releaseGroupMBID)
	if err != nil || artists == nil {
		return nil, err
	}
	out := make([]concerts.MusicArtist, len(artists))
	for i, artist := range artists {
		out[i] = concerts.MusicArtist{MusicBrainzID: artist.MusicBrainzID, Name: artist.Name}
	}
	return out, nil
}
