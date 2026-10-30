package middleware

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// The web Worker reaches the API from Cloudflare's addresses, so it names the
// visitor in X-Aaru-Visitor and proves itself with X-Aaru-Web-Secret. Only then do
// per-address limits count the visitor; anyone else naming a visitor is ignored.
func TestVisitorCountsOnlyWithTheWorkersSecret(t *testing.T) {
	for _, tc := range []struct {
		visitor, presented, secret, want string
	}{
		{"198.51.100.7", "s3cret", "s3cret", "198.51.100.7"},
		{"2001:db8::1", "s3cret", "s3cret", "2001:db8::1"},
		{" 198.51.100.7 ", "s3cret", "s3cret", "198.51.100.7"},
		{"198.51.100.7", "wrong", "s3cret", "10.0.0.1"},
		{"198.51.100.7", "", "s3cret", "10.0.0.1"},
		{"198.51.100.7", "", "", "10.0.0.1"},
		{"", "s3cret", "s3cret", "10.0.0.1"},
		{"not an ip", "s3cret", "s3cret", "10.0.0.1"},
		{"1.2.3.4, 5.6.7.8", "s3cret", "s3cret", "10.0.0.1"},
		{"1.2.3.4:443", "s3cret", "s3cret", "1.2.3.4:443"},
		{"example.com", "s3cret", "s3cret", "10.0.0.1"},
	} {
		assert.Equal(t, tc.want, RateLimitAddress(tc.visitor, tc.presented, tc.secret, "10.0.0.1"), "%+v", tc)
	}
}
