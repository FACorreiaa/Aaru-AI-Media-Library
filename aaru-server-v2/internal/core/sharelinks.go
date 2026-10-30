package core

import (
	"net/url"
	"regexp"
	"strings"
)

// ShareLinkHosts are Aaru's own hosts for share links (SHR-002).
var ShareLinkHosts = map[string]bool{"aaruapp.com": true, "www.aaruapp.com": true, "beta.aaruapp.com": true}

var shareCodePattern = regexp.MustCompile(`^[A-Za-z0-9]{1,32}$`)

// ShareLinkCode is the code of a share link (`https://aaruapp.com/s/{code}`), or ""
// for anything that is not a share link on Aaru's own hosts.
func ShareLinkCode(link string) string {
	u, err := url.Parse(link)
	if err != nil || u.Scheme != "https" || !ShareLinkHosts[u.Hostname()] {
		return ""
	}
	var parts []string
	for p := range strings.SplitSeq(u.Path, "/") {
		if p != "" {
			parts = append(parts, p)
		}
	}
	if len(parts) != 2 || parts[0] != "s" || !shareCodePattern.MatchString(parts[1]) {
		return ""
	}
	return parts[1]
}

// ShareAutoAdd is whether a shared title is saved on the way back from sign-in:
// once, and only when it is not theirs yet.
func ShareAutoAdd(add, signedIn, isTitle, unavailable, alreadyInLibrary bool) bool {
	return add && signedIn && isTitle && !unavailable && !alreadyInLibrary
}

// ShareLoadFailure is what a share link's sheet does when its preview did not load.
type ShareLoadFailure string

const (
	// ShareMissing means only an unknown code (404) says the link doesn't work.
	ShareMissing ShareLoadFailure = "missing"
	// ShareRetry means offline, rate-limited or a server error offers a retry.
	ShareRetry ShareLoadFailure = "retry"
	// ShareKeep means a failed reload after a save keeps the card already on screen.
	ShareKeep ShareLoadFailure = "keep"
)

// ShareLoadFailureAfter decides from the HTTP status (nil when the request never got
// an answer) and whether content is already showing.
func ShareLoadFailureAfter(status *int, showingContent bool) ShareLoadFailure {
	if showingContent {
		return ShareKeep
	}
	if status != nil && *status == 404 {
		return ShareMissing
	}
	return ShareRetry
}
