package main

import (
	"testing"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/egoist/mygo/ui"
)

// The view runs without a window: these tests click as a user does. The sign-in page's
// form is tested in its own package, login.

// newTester starts the view at the window's default size and lets the entrance
// animation settle. A frame after that refreshes the boxes clicks find: the animation
// only repaints until then, so the boxes of its first frame are where the card starts.
func newTester(a *app) *ui.Tester {
	tt := ui.NewTester(a.view, 960, 680)
	tt.Advance(2 * time.Second)
	tt.Frame()
	return tt
}

// newSignedInApp is an app on the page after a sign-in: the rail is there and the account
// is set. The reads it would start are not started: no window.
func newSignedInApp(p host.Page) *app {
	a := newApp(new(SmartData))
	a.acc = &account.Account{ID: "20244787"}
	a.page = p
	return a
}

// The rail's destinations change the page, and nothing else: the page is picked by
// clicking its label.
func TestNavigationRailSwitchesPages(t *testing.T) {
	a := newSignedInApp(host.PageHome)
	tt := newTester(a)
	// The 培养方案 page is not clicked here: opening it starts a school read, and a test
	// has no account to read with.
	for _, step := range []struct {
		label string
		want  host.Page
	}{
		{"爱安财", host.PageAAC},
		{"一卡通", host.PageCard},
		{"设置", host.PageSettings},
		{"首页", host.PageHome},
	} {
		if err := tt.Click(step.label); err != nil {
			t.Fatalf("click %s: %v", step.label, err)
		}
		if a.page != step.want {
			t.Errorf("after %s: page %v, want %v", step.label, a.page, step.want)
		}
	}
}

// Each signed-in page draws in the default window with no data loaded yet: the cards show
// their loading state rather than failing.
func TestSignedInPagesDraw(t *testing.T) {
	for _, p := range []host.Page{host.PageHome, host.PageAAC, host.PageLabor, host.PagePlan, host.PageCard, host.PageSettings} {
		a := newSignedInApp(p)
		tt := newTester(a)
		tt.Frame()
	}
}
