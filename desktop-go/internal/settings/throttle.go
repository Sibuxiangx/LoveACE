package settings

import (
	"log"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/userdata"
)

// cooldownLadder is the wait after the n-th wrong sign-in: none after the
// first, 30 s after the second, 2 min after the third, 10 min after every
// later one. It is the Android app's login throttle. Only a wrong password or
// a wrong captcha counts; a network error does not.
var cooldownLadder = []time.Duration{0, 30 * time.Second, 2 * time.Minute, 10 * time.Minute}

// cooldownAfter is the wait that follows the failures-th wrong sign-in.
func cooldownAfter(failures int) time.Duration {
	if failures < 1 {
		return 0
	}
	return cooldownLadder[min(failures, len(cooldownLadder))-1]
}

// failure is the wrong sign-ins of one student ID, and the time until which it
// may not sign in again.
type failure struct {
	Count int       `json:"count"`
	Until time.Time `json:"until"`
}

// Throttle keeps the failures of each student ID in throttle.json, so the
// cooldown survives a restart. Its file is "" in tests, which writes nothing.
type Throttle struct {
	file    string
	records map[string]failure
}

// LoadThrottle reads throttle.json; a missing or unreadable file gives no
// failures.
func LoadThrottle() *Throttle {
	t := &Throttle{file: "throttle.json", records: map[string]failure{}}
	if err := userdata.ReadJSON(t.file, &t.records); err != nil {
		log.Printf("throttle: %v", err)
	}
	return t
}

// NewThrottle is an empty throttle that writes nothing, for tests of the sign-in
// page; LoadThrottle is the one the app uses.
func NewThrottle() *Throttle {
	return &Throttle{records: map[string]failure{}}
}

// Remaining is how long id must still wait; 0 when it may sign in now.
func (t *Throttle) Remaining(id string, now time.Time) time.Duration {
	if d := t.records[id].Until.Sub(now); d > 0 {
		return d
	}
	return 0
}

// Fail counts a wrong password or captcha for id and starts its cooldown. It
// returns the cooldown that now applies.
func (t *Throttle) Fail(id string, now time.Time) time.Duration {
	r := t.records[id]
	r.Count++
	r.Until = now.Add(cooldownAfter(r.Count))
	t.records[id] = r
	t.persist()
	return cooldownAfter(r.Count)
}

// Clear forgets the failures of id after a successful sign-in.
func (t *Throttle) Clear(id string) {
	delete(t.records, id)
	t.persist()
}

func (t *Throttle) persist() {
	if t.file == "" {
		return
	}
	if err := userdata.WriteJSON(t.file, t.records); err != nil {
		log.Printf("throttle: %v", err)
	}
}
