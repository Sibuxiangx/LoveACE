// Package host is the contract between the app shell and its pages: what a page may
// ask of the shell, and the background read every page runs against the school.
package host

import (
	"context"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
)

// Page is a page of the app, as the navigation rail opens it.
type Page int

const (
	PageLogin Page = iota
	PageHome
	PageAAC
	PageLabor
	PagePlan
	PageCard
	PageSmart
	PageSettings
)

// Host is what a page asks of the app shell. The shell implements it; a page never
// holds the shell itself.
type Host interface {
	// Account is the signed-in school account, nil while signed out.
	Account() *account.Account
	// Update runs fn on the main thread and redraws the window.
	Update(fn func())
	// Open shows page p, as the navigation rail does.
	Open(p Page)
}

// readTimeout bounds one read of the school's systems, so a stalled read does not
// leave its card loading for ever.
const readTimeout = 30 * time.Second

// Start runs run in the background for acc. Its apply reaches the page on the main
// thread, and is dropped when the account was signed out or changed during the read.
func Start(h Host, acc *account.Account, run func(ctx context.Context, apply func(func()))) {
	apply := func(fn func()) {
		h.Update(func() {
			if h.Account() == acc {
				fn()
			}
		})
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), readTimeout)
		defer cancel()
		run(ctx, apply)
	}()
}
