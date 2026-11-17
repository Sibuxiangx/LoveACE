package main

import (
	"testing"
	"time"
)

func TestCooldownLadder(t *testing.T) {
	want := []time.Duration{
		0, 30 * time.Second, 2 * time.Minute, 10 * time.Minute,
		10 * time.Minute, 10 * time.Minute,
	}
	for i, w := range want {
		if got := cooldownAfter(i + 1); got != w {
			t.Errorf("after %d failures: %v, want %v", i+1, got, w)
		}
	}
	if got := cooldownAfter(0); got != 0 {
		t.Errorf("after 0 failures: %v, want 0", got)
	}
}

func TestThrottleCountsAndExpires(t *testing.T) {
	th := &throttle{records: map[string]failure{}}
	now := time.Unix(1_700_000_000, 0)

	th.fail("2024001", now) // first wrong password: no wait
	if d := th.remaining("2024001", now); d != 0 {
		t.Fatalf("after one failure: remaining %v, want 0", d)
	}

	th.fail("2024001", now) // second: 30 s
	if d := th.remaining("2024001", now.Add(10*time.Second)); d != 20*time.Second {
		t.Errorf("10 s into the cooldown: remaining %v, want 20s", d)
	}
	if d := th.remaining("2024001", now.Add(31*time.Second)); d != 0 {
		t.Errorf("after the cooldown: remaining %v, want 0", d)
	}
	if d := th.remaining("2024002", now); d != 0 {
		t.Errorf("another student: remaining %v, want 0", d)
	}

	th.clear("2024001")
	if d := th.remaining("2024001", now); d != 0 {
		t.Errorf("after a successful sign-in: remaining %v, want 0", d)
	}
}
