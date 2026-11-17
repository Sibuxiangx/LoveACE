package home

import (
	"math"
	"testing"
	"time"
)

// The hands point where the time says: twelve o'clock is zero, and each hand
// moves clockwise from there. The hour hand moves with the minutes too.
func TestClockFractions(t *testing.T) {
	cases := []struct {
		name                 string
		at                   time.Time
		hour, minute, second float64
	}{
		{"twelve sharp", time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC), 0, 0, 0},
		{"three fifteen and thirty seconds", time.Date(2026, 11, 16, 15, 15, 30, 0, time.UTC), (3 + 15.5/60) / 12, 15.5 / 60, 30.0 / 60},
		{"afternoon hour wraps to the dial", time.Date(2026, 11, 16, 23, 30, 0, 0, time.UTC), 11.5 / 12, 0.5, 0},
	}
	for _, c := range cases {
		hour, minute, second := clockFractions(c.at)
		for _, pair := range [][2]float64{{hour, c.hour}, {minute, c.minute}, {second, c.second}} {
			if math.Abs(pair[0]-pair[1]) > 1e-9 {
				t.Errorf("%s: got hour %.6f minute %.6f second %.6f, want %.6f %.6f %.6f",
					c.name, hour, minute, second, c.hour, c.minute, c.second)
				break
			}
		}
	}
}
