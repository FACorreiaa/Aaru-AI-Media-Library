package reviewseed

import "aaru-go-api/internal/core"

// The two accounts' handles and names.
const (
	ReviewHandle    = "appreview"
	ReviewFirstName = "App"
	ReviewLastName  = "Review"
	FriendHandle    = "mira_reads"
	FriendFirstName = "Mira"
	GroupName       = "Film club"
)

// Seed is one library item: the title by its provider id, and what the account did with it.
type Seed struct {
	// Name is for the log line of a title that did not resolve; the provider's own title wins.
	Name   string
	Ref    core.MediaRef
	Status core.LibraryStatus
	Rating *float64
	Notes  *string
	// Episodes ticks this many of the show's first aired episodes (season 1 on).
	Episodes int
	// MangaChapter is the last chapter read.
	MangaChapter *int
}

func f(v float64) *float64 { return &v }
func s(v string) *string   { return &v }
func n(v int) *int         { return &v }

func movie(name, tmdb string) core.MediaRef {
	return core.MediaRef{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: tmdb}, Title: s(name)}
}

func show(name, tmdb string) core.MediaRef {
	return core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: tmdb}, Title: s(name)}
}

// anime is a show by its AniList id: it lands on the TMDB show where anime_mappings has one.
func anime(name, anilist string) core.MediaRef {
	return core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: anilist}, Title: s(name)}
}

func manga(name, anilist string) core.MediaRef {
	return core.MediaRef{Type: core.MediaManga, IDs: core.ExternalIDs{AniList: anilist}, Title: s(name)}
}

func book(name, work string) core.MediaRef {
	return core.MediaRef{Type: core.MediaBook, IDs: core.ExternalIDs{OpenLibrary: work}, Title: s(name)}
}

func album(name, mbid string) core.MediaRef {
	return core.MediaRef{Type: core.MediaAlbum, IDs: core.ExternalIDs{MusicBrainz: mbid}, Title: s(name)}
}

// The titles, by provider id: TMDB movie and tv ids, AniList ids (anime and manga), Open Library
// work ids, MusicBrainz release-group ids. All well known and none adult.
var (
	paddington2   = movie("Paddington 2", "346648")
	grandBudapest = movie("The Grand Budapest Hotel", "120467")
	spiritedAway  = movie("Spirited Away", "129")
	dunePartTwo   = movie("Dune: Part Two", "693134")
	arrival       = movie("Arrival", "329865")
	severance     = show("Severance", "95396")
	theBear       = show("The Bear", "136315")
	tedLasso      = show("Ted Lasso", "97546")
	frieren       = anime("Frieren: Beyond Journey's End", "154587")
	cowboyBebop   = anime("Cowboy Bebop", "1")
	yotsuba       = manga("Yotsuba&!", "30104")
	theHobbit     = book("The Hobbit", "OL27482W")
	pridePrejud   = book("Pride and Prejudice", "OL66554W")
	abbeyRoad     = album("Abbey Road", "9162580e-5df4-32de-80cc-f45a8d8a9b1d")
	kindOfBlue    = album("Kind of Blue", "8e8a594f-2175-38c7-a871-abb68ec363e7")
	rumours       = album("Rumours", "416bb5e5-c7d1-3977-8fd7-7c9daf6c2be6")
)

// ReviewLibrary is the review account's library: 15 items over every kind, every status, two
// ratings and one note; two shows in progress with ticked episodes for Up Next and the week.
var ReviewLibrary = []Seed{
	{Name: "Paddington 2", Ref: paddington2, Status: core.StatusFinished, Rating: f(9)},
	{Name: "The Grand Budapest Hotel", Ref: grandBudapest, Status: core.StatusFinished, Rating: f(8.5), Notes: s("Watch again with the film club.")},
	{Name: "Spirited Away", Ref: spiritedAway, Status: core.StatusFinished},
	{Name: "Dune: Part Two", Ref: dunePartTwo, Status: core.StatusWishlist},
	{Name: "Arrival", Ref: arrival, Status: core.StatusWishlist},
	{Name: "Severance", Ref: severance, Status: core.StatusInProgress, Episodes: 3},
	{Name: "The Bear", Ref: theBear, Status: core.StatusInProgress, Episodes: 4},
	{Name: "Ted Lasso", Ref: tedLasso, Status: core.StatusOnHold},
	{Name: "Frieren: Beyond Journey's End", Ref: frieren, Status: core.StatusInProgress, Episodes: 2},
	{Name: "Cowboy Bebop", Ref: cowboyBebop, Status: core.StatusWishlist},
	{Name: "Yotsuba&!", Ref: yotsuba, Status: core.StatusInProgress, MangaChapter: n(12)},
	{Name: "The Hobbit", Ref: theHobbit, Status: core.StatusFinished},
	{Name: "Pride and Prejudice", Ref: pridePrejud, Status: core.StatusInProgress},
	{Name: "Abbey Road", Ref: abbeyRoad, Status: core.StatusFinished},
	{Name: "Kind of Blue", Ref: kindOfBlue, Status: core.StatusWishlist},
}

// FriendLibrary is Mira's: enough for her profile to show something.
var FriendLibrary = []Seed{
	{Name: "Paddington 2", Ref: paddington2, Status: core.StatusFinished, Rating: f(9)},
	{Name: "Spirited Away", Ref: spiritedAway, Status: core.StatusFinished},
	{Name: "Pride and Prejudice", Ref: pridePrejud, Status: core.StatusFinished},
	{Name: "Frieren: Beyond Journey's End", Ref: frieren, Status: core.StatusInProgress},
	{Name: "Rumours", Ref: rumours, Status: core.StatusFinished},
}

// The Board: Mira's post about PostTitle, her comment on it, and the reviewer's.
var (
	PostTitle         = paddington2
	PostRating        = 9.0
	PostBody          = "A perfect rainy-day film. It still makes me smile every time."
	FriendCommentBody = "Watching it again this weekend with my sister."
	ReviewCommentBody = "Agreed, it is a lovely film. The first one is on my list too."
)

// Message is one #general message, by the friend unless ByReviewer. Nonce is its client nonce:
// posting it again returns the first one, so a second run adds nothing.
type Message struct {
	Nonce      string
	Body       string
	ByReviewer bool
}

// GroupMessages are the #general messages of the friend's group, in order.
var GroupMessages = []Message{
	{Nonce: "review-seed-1", Body: "Welcome to the film club! One film a week, then we talk about it here."},
	{Nonce: "review-seed-2", Body: "This week it is Paddington 2. No spoilers before Friday, please."},
	{Nonce: "review-seed-3", Body: "Count me in. I watched it last month and would happily watch it again.", ByReviewer: true},
	{Nonce: "review-seed-4", Body: "Lovely. Next week I would like to try Spirited Away."},
	{Nonce: "review-seed-5", Body: "Friday at eight works for me. Bring snacks!"},
}
