package core

import (
	"strings"
	"time"

	"github.com/google/uuid"
)

// LibraryItem is one user's relationship to one title.
//
// The library layer. Catalog facts (name, year, poster, provider ids) live on
// Title and are never copied here.
type LibraryItem struct {
	ID      uuid.UUID
	UserID  uuid.UUID
	TitleID uuid.UUID
	// Status is consumption state only.
	Status LibraryStatus
	// IsOwned is ownership, independent of consumption. A wishlist item can be owned.
	IsOwned    bool
	Rating     *Rating
	Notes      *string
	Progress   *Progress
	AddedAt    time.Time
	UpdatedAt  time.Time
	FinishedAt *time.Time
}

// AaruList is a user-curated collection of titles. The domain word stays "list"
// in the API and the UI.
//
// Members are title ids, not library item ids, so a list can hold a title the
// user has not given a status yet.
type AaruList struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	Name      string
	TitleIDs  []uuid.UUID
	CreatedAt time.Time
	UpdatedAt time.Time
}

// Validate rejects a blank name.
func (l AaruList) Validate() error {
	return ValidateListName(l.Name)
}

// ValidateListName rejects a name that is empty after trimming whitespace.
func ValidateListName(name string) error {
	if strings.TrimSpace(name) == "" {
		return &ValidationError{Kind: EmptyListName}
	}
	return nil
}
