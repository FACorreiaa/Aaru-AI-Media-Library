package middleware

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// Ported from ConcertTests.swift (redaction): the city search is not logged with its query.
func TestTheConcertCitySearchIsNotLoggedWithItsQuery(t *testing.T) {
	assert.Equal(t, "/v1/concerts/places", Redacted("/v1/concerts/places", "q=Lisboa"))
}
