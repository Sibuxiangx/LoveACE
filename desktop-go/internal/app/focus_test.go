package app

import (
	"testing"
	"time"
)

// Only a real absence triggers a refresh: a brief switch to another app, or an app
// that never left, reads nothing.
func TestShouldRefreshOnFocus(t *testing.T) {
	now := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	cases := []struct {
		name   string
		leftAt time.Time
		want   bool
	}{
		{"never left", time.Time{}, false},
		{"switched away briefly", now.Add(-30 * time.Second), false},
		{"away for a minute", now.Add(-time.Minute), true},
		{"away for hours", now.Add(-3 * time.Hour), true},
	}
	for _, c := range cases {
		if got := shouldRefreshOnFocus(c.leftAt, now); got != c.want {
			t.Errorf("%s: shouldRefreshOnFocus = %v, want %v", c.name, got, c.want)
		}
	}
}
