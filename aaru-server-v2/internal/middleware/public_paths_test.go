package middleware

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// InviteTests.publicPaths: only a bare invite code is public.
func TestOnlyABareInviteCodeIsPublic(t *testing.T) {
	assert.True(t, IsPublic("/v1/invites/abc123"))
	assert.False(t, IsPublic("/v1/invites/"))
	assert.False(t, IsPublic("/v1/invites/abc/redeem"))
	assert.False(t, IsPublic("/v1/social/invites"))
	assert.True(t, IsPublic("/v1/health"))
}

// ShareTests.publicPath: only a share's preview path is public.
func TestOnlyAShareCodesPreviewPathIsPublic(t *testing.T) {
	assert.True(t, IsPublic("/v1/shares/abc"))
	assert.False(t, IsPublic("/v1/shares/"))
	assert.False(t, IsPublic("/v1/shares"))
	assert.False(t, IsPublic("/v1/shares/abc/x"))
	assert.True(t, IsPublic("/v1/invites/abc"), "invites stay public")
}
