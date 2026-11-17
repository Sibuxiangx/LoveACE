package read

import (
	"context"
	"testing"
	"time"

	"github.com/Sibuxiangx/loveace-go/core/errs"
)

// noReadDelays makes the waits between the tries of a read zero for one test, and
// restores them after.
func noReadDelays(t *testing.T) {
	t.Helper()
	saved := readAttemptDelays
	readAttemptDelays = []time.Duration{0, 0}
	t.Cleanup(func() { readAttemptDelays = saved })
}

// A network failure is tried three times in all, and the last error is the one kept.
func TestReadRetryTriesRetryableErrorsThreeTimes(t *testing.T) {
	noReadDelays(t)
	calls := 0
	_, err := Retry(context.Background(), func(context.Context) (int, error) {
		calls++
		return 0, errs.NewNetwork("down")
	})
	if calls != 3 {
		t.Errorf("calls = %d, want 3", calls)
	}
	if got := errs.CodeOf(err); got != errs.Network {
		t.Errorf("code = %v, want %v", got, errs.Network)
	}
}

// A read that works on a later try returns what that try read.
func TestReadRetryReturnsLaterSuccess(t *testing.T) {
	noReadDelays(t)
	calls := 0
	v, err := Retry(context.Background(), func(context.Context) (int, error) {
		calls++
		if calls < 2 {
			return 0, errs.NewTimeout(30)
		}
		return 7, nil
	})
	if err != nil || v != 7 || calls != 2 {
		t.Errorf("v=%d err=%v calls=%d, want 7, nil, 2", v, err, calls)
	}
}

// A page that does not parse is what a read gets while the school's session is
// still being set up after sign-in, so it is tried again.
func TestReadRetryRepeatsParseErrors(t *testing.T) {
	noReadDelays(t)
	calls := 0
	v, err := Retry(context.Background(), func(context.Context) (int, error) {
		calls++
		if calls < 2 {
			return 0, errs.NewParse("academicInfo: expected non-empty array")
		}
		return 3, nil
	})
	if err != nil || v != 3 || calls != 2 {
		t.Errorf("v=%d err=%v calls=%d, want 3, nil, 2", v, err, calls)
	}
}

// A wrong password is not a failure a repeat can fix, so it is tried once.
func TestReadRetryDoesNotRepeatCredentialErrors(t *testing.T) {
	noReadDelays(t)
	calls := 0
	_, err := Retry(context.Background(), func(context.Context) (int, error) {
		calls++
		return 0, errs.NewInvalidCredentials()
	})
	if calls != 1 {
		t.Errorf("calls = %d, want 1", calls)
	}
	if got := errs.CodeOf(err); got != errs.InvalidCredentials {
		t.Errorf("code = %v, want %v", got, errs.InvalidCredentials)
	}
}

// A cancelled read stops at once: its context is over, so a repeat would only fail.
func TestReadRetryDoesNotRepeatCancelled(t *testing.T) {
	noReadDelays(t)
	calls := 0
	_, err := Retry(context.Background(), func(context.Context) (int, error) {
		calls++
		return 0, errs.NewCancelled()
	})
	if calls != 1 {
		t.Errorf("calls = %d, want 1", calls)
	}
	if got := errs.CodeOf(err); got != errs.Cancelled {
		t.Errorf("code = %v, want %v", got, errs.Cancelled)
	}
}
