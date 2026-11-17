package app

import (
	"github.com/Sibuxiangx/loveace-desktop/internal/aac"
	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/card"
	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/electricity"
	"github.com/Sibuxiangx/loveace-desktop/internal/exam"
	"github.com/Sibuxiangx/loveace-desktop/internal/home"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/labor"
	"github.com/Sibuxiangx/loveace-desktop/internal/login"
	"github.com/Sibuxiangx/loveace-desktop/internal/plan"
	"github.com/Sibuxiangx/loveace-desktop/internal/portal"
	"github.com/Sibuxiangx/loveace-desktop/internal/repair"
	"github.com/Sibuxiangx/loveace-desktop/internal/settings"
	"github.com/Sibuxiangx/loveace-desktop/internal/timetable"
	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
)

// app is the shell of the window: the page on screen, the signed-in account, and the
// pages. It is the host.Host the pages talk to. The view builds the interface from it
// on the main thread; background reads change a page only on the main thread too.
type app struct {
	win          *mygo.Window
	page         host.Page
	acc          *account.Account // nil exactly when the page is the sign-in page
	settingsPage *settings.Page
	set          *settings.Settings
	throttle     *settings.Throttle
	login        *login.Feature
	home         *home.Feature
	aac          *aac.Feature
	card         *card.Feature
	plan         *plan.Feature
	labor        *labor.Feature
	portal       *portal.Feature
	repair       *repair.Feature
	electricity  *electricity.Feature
	exam         *exam.Feature
	timetable    *timetable.Feature
	smartWin     *mygo.Window // the 智能排课 window, nil while it is closed
	// data is the school data of the smart window; its account follows acc.
	data *SmartData
}

// newApp reads the saved settings and the cooldowns, and makes the pages. Call it once
// the app is ready, since the user data directory is known only then.
func newApp(data *SmartData) *app {
	a := &app{page: host.PageLogin, data: data}
	a.throttle = settings.LoadThrottle()
	a.settingsPage = settings.New(a, a.signOut)
	a.set = a.settingsPage.Settings()
	a.aac = aac.New(a)
	a.card = card.New(a)
	a.plan = plan.New(a)
	a.labor = labor.New(a)
	a.portal = portal.New(a)
	a.repair = repair.New(a)
	a.electricity = electricity.New(a)
	a.exam = exam.New(a)
	a.timetable = timetable.New(a)
	a.home = home.New(a, a.aac, a.card)
	a.login = login.New(a, a.throttle, a.set, a.signedIn)
	return a
}

// Account is the signed-in school account, nil while signed out.
func (a *app) Account() *account.Account { return a.acc }

// Update runs fn on the main thread and redraws the window.
func (a *app) Update(fn func()) { a.win.Update(fn) }

// Open shows page p, as the navigation rail does.
func (a *app) Open(p host.Page) { a.openPage(p) }

// view draws the current page. The scheme is read before SetTheme, because the
// appearance can follow the system's theme.
func (a *app) view(c *ui.Context) {
	s, dark := a.appearance(c)
	t := design.ThemeOf(c, s, dark)
	c.SetTheme(t)
	if a.page == host.PageLogin {
		a.login.View(c, t)
		return
	}
	c.Root().Background(t.Background)
	x := design.ExtendedOf(dark)
	ui.Row(c).Fill().AlignItems(ui.Stretch).Children(func() {
		a.navRail(c, t, s)
		ui.Column(c).Grow(1).MinWidth(0).Children(func() {
			switch a.page {
			case host.PageHome:
				a.home.View(c, t, s, x)
			case host.PageAAC:
				a.aac.View(c, t, s, x)
			case host.PagePlan:
				a.plan.View(c, t, s, x)
			case host.PageCard:
				a.card.View(c, t, s, x)
			case host.PageLabor:
				a.labor.View(c, t, s, x)
			case host.PagePortal:
				a.portal.View(c, t, s)
			case host.PageRepair:
				a.repair.View(c, t, s)
			case host.PageElectricity:
				a.electricity.View(c, t, s)
			case host.PageExam:
				a.exam.View(c, t, s)
			case host.PageTimetable:
				a.timetable.View(c, t, s)
			case host.PageSettings:
				a.settingsPage.View(c, t, s)
			}
		})
	})
}

// signedIn makes acc the signed-in account and opens the home page, reading its data
// in the background.
func (a *app) signedIn(acc *account.Account) {
	a.acc = acc
	a.data.acc.Store(acc)
	a.page = host.PageHome
	a.home.Load()
	a.aac.Load()
	a.card.Load()
}

// openPage shows a page chosen on the navigation rail. The 培养方案, 劳动俱乐部, 借阅门禁, 零星维修,
// 电费, 考试安排, 课程表 pages read the first time they open; the other pages are read at
// sign-in. Leaving the settings page forgets the mail password it showed.
func (a *app) openPage(p host.Page) {
	a.page = p
	if p == host.PagePlan && !a.plan.Snapshot().Info.Loaded() {
		a.plan.Load(a.plan.Snapshot().PlanID)
	}
	if p == host.PageLabor && !a.labor.Snapshot().Joined.Loaded() {
		a.labor.Load()
	}
	switch p {
	case host.PagePortal:
		a.portal.Open()
	case host.PageRepair:
		a.repair.Open()
	case host.PageElectricity:
		a.electricity.Open()
	case host.PageExam:
		a.exam.Open()
	case host.PageTimetable:
		a.timetable.Open()
	}
	if p != host.PageSettings {
		a.settingsPage.Leave()
	}
}

// signOut ends the session. The settings page has already forgotten the remembered
// password and saved the settings; here the account is dropped and every page's data
// goes with it.
func (a *app) signOut() {
	a.acc = nil
	a.data.acc.Store(nil)
	a.home.Reset()
	a.aac.Reset()
	a.card.Reset()
	a.plan.Reset()
	a.labor.Reset()
	a.portal.Reset()
	a.repair.Reset()
	a.electricity.Reset()
	a.exam.Reset()
	a.timetable.Reset()
	a.login.Reset()
	a.page = host.PageLogin
}
