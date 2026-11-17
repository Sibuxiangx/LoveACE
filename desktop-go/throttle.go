package main

import (
	"log"
	"time"
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

// throttle keeps the failures of each student ID in throttle.json, so the
// cooldown survives a restart. Its file is "" in tests, which writes nothing.
type throttle struct {
	file    string
	records map[string]failure
}

func loadThrottle() *throttle {
	t := &throttle{file: "throttle.json", records: map[string]failure{}}
	if err := readJSON(t.file, &t.records); err != nil {
		log.Printf("throttle: %v", err)
	}
	return t
}

// remaining is how long id must still wait; 0 when it may sign in now.
func (t *throttle) remaining(id string, now time.Time) time.Duration {
	if d := t.records[id].Until.Sub(now); d > 0 {
		return d
	}
	return 0
}

// fail counts a wrong password or captcha for id and starts its cooldown. It
// returns the cooldown that now applies.
func (t *throttle) fail(id string, now time.Time) time.Duration {
	r := t.records[id]
	r.Count++
	r.Until = now.Add(cooldownAfter(r.Count))
	t.records[id] = r
	t.persist()
	return cooldownAfter(r.Count)
}

// clear forgets the failures of id after a successful sign-in.
func (t *throttle) clear(id string) {
	delete(t.records, id)
	t.persist()
}

func (t *throttle) persist() {
	if t.file == "" {
		return
	}
	if err := writeJSON(t.file, t.records); err != nil {
		log.Printf("throttle: %v", err)
	}
}
