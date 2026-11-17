package main

import (
	"context"
	"errors"
	"log"
	"time"

	"github.com/Sibuxiangx/loveace-go/core/errs"
)

// readTimeout bounds one read of the school's systems, so a stalled read does
// not leave its card loading for ever.
const readTimeout = 30 * time.Second

// applyFn applies a change to the app, on the main thread.
type applyFn func(func(*app))

// startRead runs read in the background for acc. Its changes reach the app on
// the main thread, and are dropped when the account was signed out or changed
// during the read.
func (a *app) startRead(acc *account, read func(ctx context.Context, apply applyFn)) {
	apply := func(fn func(*app)) {
		a.win.Update(func() {
			if a.acc == acc {
				fn(a)
			}
		})
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), readTimeout)
		defer cancel()
		read(ctx, apply)
	}()
}

// readAttemptDelays are the waits before the second and third try of a read that
// failed in a way a repeat can fix. loveace-go already retries each request; these
// wait longer between whole reads, for a school that is slow to answer just after
// sign-in.
var readAttemptDelays = []time.Duration{2 * time.Second, 5 * time.Second}

// readRetry runs one read of the school, and runs it again after a wait while it
// fails with an error a repeat can fix. A read changes nothing on the school's
// side, so repeating one is safe. The tries share the read's readTimeout. The last
// error is returned, so the card still says why the read failed; its code is also
// logged, because the card's wording does not name it.
func readRetry[T any](ctx context.Context, read func(context.Context) (T, error)) (T, error) {
	var v T
	var err error
	for try := 0; ; try++ {
		v, err = read(ctx)
		if err == nil || try == len(readAttemptDelays) || !retryableRead(err) || !waitRetry(ctx, readAttemptDelays[try]) {
			break
		}
	}
	if err != nil {
		log.Printf("read failed: %v", errs.CodeOf(err))
	}
	return v, err
}

// waitRetry waits d before another try. It is false when the read's context ends
// first, so a read stops at its timeout.
func waitRetry(ctx context.Context, d time.Duration) bool {
	select {
	case <-ctx.Done():
		return false
	case <-time.After(d):
		return true
	}
}

// neverRetried are the errors a repeat cannot fix: the sign-in needs the user, the
// read was cancelled, or the request is wrong.
var neverRetried = map[errs.Code]bool{
	errs.InvalidCredentials:         true,
	errs.AuthRequired:               true,
	errs.MaybeAttacked:              true,
	errs.InteractionRequired:        true,
	errs.PasswordChangeRequired:     true,
	errs.NonAsciiCredential:         true,
	errs.Cancelled:                  true,
	errs.InvalidArgument:            true,
	errs.NotImplemented:             true,
	errs.UnsupportedManifestVersion: true,
}

// retryableRead is whether a read error is one a repeat can fix. Every school error
// is retried except those in neverRetried. That includes a page that does not parse,
// which a read gets while the school's session is still being set up after sign-in,
// and a session recovery that failed, which loveace-go does not retry on its own.
func retryableRead(err error) bool {
	var e *errs.Error
	return errors.As(err, &e) && !neverRetried[e.Code]
}

// readState is one read of a page: whether it has finished, what it said when
// it failed, and what it read.
type readState[T any] struct {
	loaded bool
	err    string
	v      T
}

// readErrText is the wording a page shows for a failed read. The wording follows
// the error's code, and says what the user can do; a failed read never clears
// the account, so the user can retry without signing in.
func readErrText(err error) string {
	if err == nil {
		return ""
	}
	if errors.Is(err, errNoTermStart) {
		return "学期配置里还没有本学期的开学日期，无法确定教学周"
	}
	var e *errs.Error
	if errors.As(err, &e) {
		switch e.Code {
		case errs.InvalidCredentials, errs.AuthRequired, errs.MaybeAttacked,
			errs.InteractionRequired, errs.PasswordChangeRequired:
			return "学校登录已失效，请退出后重新登录"
		case errs.Network, errs.Timeout, errs.HTTP, errs.Throttled, errs.TemporarilyUnavailable:
			return "连不上学校的教务系统，请检查网络后刷新"
		}
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return "连不上学校的教务系统，请检查网络后刷新"
	}
	return "读取失败，请稍后刷新"
}
