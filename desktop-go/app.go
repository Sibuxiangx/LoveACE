package main

import (
	"log"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
)

// page is the screen the window shows. Signed out, the window shows only the
// sign-in page; signed in, the navigation rail picks one of the others.
type page int

const (
	pageLogin page = iota
	pageHome
	pageAAC
	pageLabor
	pagePlan
	pageCard
	pageSettings
)

// app is the state of the window. The view builds the interface from it on
// the main thread; background work changes it only inside the reads' apply.
type app struct {
	win      *mygo.Window
	page     page
	settings settings
	throttle *throttle
	// acc is the signed-in school session. It is nil exactly when the page is
	// the sign-in page, which the views rely on.
	acc      *account
	login    loginForm
	home     homeState
	aac      aacState
	card     cardState
	plan     planState
	labor    laborState
	smartWin *mygo.Window // the 智能排课 window, nil while it is closed
	// data is the school data of the smart window; its account follows acc.
	data *SmartData
}

// newApp reads the saved settings and the cooldowns. Call it once the app is
// ready, since the user data directory is known only then.
func newApp(data *SmartData) *app {
	return &app{page: pageLogin, settings: loadSettings(), throttle: loadThrottle(), data: data}
}

// view draws the current page. The scheme is read before SetTheme, because the
// appearance can follow the system's theme.
func (a *app) view(c *ui.Context) {
	s, dark := a.appearance(c)
	t := themeOf(c, s, dark)
	c.SetTheme(t)
	if a.page == pageLogin {
		a.loginView(c, t)
		return
	}
	c.Root().Background(t.Background)
	x := extendedOf(dark)
	ui.Row(c).Fill().AlignItems(ui.Stretch).Children(func() {
		a.navRail(c, t, s)
		ui.Column(c).Grow(1).MinWidth(0).Children(func() {
			switch a.page {
			case pageHome:
				a.homeView(c, t, s, x)
			case pageAAC:
				a.aacView(c, t, s, x)
			case pagePlan:
				a.planView(c, t, s, x)
			case pageCard:
				a.cardView(c, t, s)
			case pageLabor:
				a.laborView(c, t, s, x)
			case pageSettings:
				a.settingsView(c, t, s)
			}
		})
	})
}

// signedIn makes acc the signed-in account and opens the home page, reading its
// data in the background.
func (a *app) signedIn(acc *account) {
	a.acc = acc
	a.data.acc.Store(acc)
	a.page = pageHome
	a.loadHome()
	a.loadAAC()
	a.loadCard()
}

// openPage shows a page chosen on the navigation rail. The 培养方案, 劳动俱乐部 and 智能排课
// pages read the first time they open; the other pages are read at sign-in.
func (a *app) openPage(p page) {
	a.page = p
	if p == pagePlan && !a.plan.info.loaded {
		a.loadPlan(a.plan.planID)
	}
	if p == pageLabor && !a.labor.joined.loaded {
		a.loadLabor()
	}
}

// signOut ends the session. The account is dropped, the remembered password is
// removed from the credential store, and every page's data goes with it.
func (a *app) signOut() {
	a.dropRemembered()
	a.saveSettings()
	a.acc = nil
	a.data.acc.Store(nil)
	a.home = homeState{}
	a.aac = aacState{}
	a.card = cardState{}
	a.plan = planState{}
	a.labor = laborState{}
	a.login = loginForm{}
	a.page = pageLogin
}

// saveSettings writes settings.json. A failure is logged; the in-memory
// settings still apply for this run.
func (a *app) saveSettings() {
	if err := a.settings.save(); err != nil {
		log.Printf("settings: %v", err)
	}
}
