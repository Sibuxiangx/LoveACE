package app

import (
	"crypto/sha256"
	"encoding/hex"
	"log"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/userdata"
)

// cacheTTL is how long a school read of the smart page is reused before the school is asked
// again. Opening the page or switching terms must not read the same things again; only the
// refresh button asks at once.
const cacheTTL = 30 * time.Minute

// cacheFresh reports whether a read taken at fetchedAt is still reused at now. An age that
// is negative (the clock went back) counts as stale.
func cacheFresh(fetchedAt, now time.Time) bool {
	age := now.Sub(fetchedAt)
	return age >= 0 && age < cacheTTL
}

// stamped is a cached read and when the school gave it.
type stamped[T any] struct {
	FetchedAt int64 `json:"fetched_at"` // Unix milliseconds
	Value     T     `json:"value"`
}

// cacheFile is the file name of one cached read of kind for the student accountID. key tells
// apart reads of one kind. The name is a hash, so whatever the school sends stays a plain
// file name in the user data directory.
func cacheFile(kind, accountID, key string) string {
	sum := sha256.Sum256([]byte(kind + "\x00" + accountID + "\x00" + key))
	return "smart_" + kind + "_" + hex.EncodeToString(sum[:]) + ".json"
}

// cachedRead returns the value cached under name while it is fresh. Otherwise it asks the
// school with fetch and caches the value. A failed read is not cached. A failed save is
// logged, since the value was still read.
func cachedRead[T any](name string, fetch func() (T, error)) (T, error) {
	var cached stamped[T]
	if err := userdata.ReadJSON(name, &cached); err == nil && cached.FetchedAt != 0 &&
		cacheFresh(time.UnixMilli(cached.FetchedAt), time.Now()) {
		return cached.Value, nil
	}
	value, err := fetch()
	if err != nil {
		return value, err
	}
	fresh := stamped[T]{FetchedAt: time.Now().UnixMilli(), Value: value}
	if err := userdata.WriteJSON(name, fresh); err != nil {
		log.Printf("smart cache: save: %v", err)
	}
	return value, nil
}
