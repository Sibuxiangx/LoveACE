package app

import (
	"crypto/sha256"
	"encoding/hex"

	"github.com/Sibuxiangx/loveace-desktop/internal/userdata"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// Offerings is one term's course offerings, and when the school gave them. They are cached
// as a file of their own: reading a whole term takes one request per page.
type Offerings struct {
	FetchedAt int64                      `json:"fetched_at"` // Unix milliseconds
	Records   []jwc.CourseScheduleRecord `json:"records"`
}

// offeringsFile is the file name of the offerings of termCode for the student accountID.
// The name is a hash of both, so whatever the school sends (a term code, or a plan code in
// class mode) stays a plain file name in the user data directory.
func offeringsFile(accountID, termCode string) string {
	sum := sha256.Sum256([]byte(accountID + "\x00" + termCode))
	return "smart_offerings_" + hex.EncodeToString(sum[:]) + ".json"
}

// loadOfferings reads the cached offerings of a term, and false when there are none.
func loadOfferings(name string) (Offerings, bool) {
	var cached Offerings
	if err := userdata.ReadJSON(name, &cached); err != nil || cached.FetchedAt == 0 {
		return Offerings{}, false
	}
	return cached, true
}
