package app

import (
	"strings"
	"testing"
	"time"
)

// A cached read is reused for thirty minutes, and a clock that went back is stale.
func TestCacheFreshWithinThirtyMinutes(t *testing.T) {
	fetched := time.Date(2026, 11, 17, 10, 0, 0, 0, time.Local)
	cases := []struct {
		name string
		age  time.Duration
		want bool
	}{
		{"just fetched", 0, true},
		{"29 minutes old", 29 * time.Minute, true},
		{"exactly 30 minutes old", 30 * time.Minute, false},
		{"31 minutes old", 31 * time.Minute, false},
		{"clock went back", -time.Minute, false},
	}
	for _, c := range cases {
		if got := cacheFresh(fetched, fetched.Add(c.age)); got != c.want {
			t.Errorf("%s: fresh = %v, want %v", c.name, got, c.want)
		}
	}
}

// Each (account, term) has its own offerings file, the same name every time, and a name that
// is a single plain file in the user data directory whatever the term code holds.
func TestOfferingsFileNamePerTermIsPlain(t *testing.T) {
	a := offeringsFile("20244787", "2026-2027-1-1")
	if a != offeringsFile("20244787", "2026-2027-1-1") {
		t.Error("the same term must give the same file")
	}
	if a == offeringsFile("20244787", "2026-2027-1-2") {
		t.Error("two terms must not share a file")
	}
	if a == offeringsFile("20244788", "2026-2027-1-1") {
		t.Error("two accounts must not share a file")
	}
	for _, term := range []string{"2026-2027-1-1", "../etc/passwd", "plan/with/slash", "a b", ""} {
		name := offeringsFile("20244787", term)
		if strings.ContainsAny(name, `/\`) || strings.Contains(name, "..") {
			t.Errorf("term %q gave a path-like name %q", term, name)
		}
		if !strings.HasPrefix(name, "smart_offerings_") || !strings.HasSuffix(name, ".json") {
			t.Errorf("term %q gave %q", term, name)
		}
	}
}
