package app

import (
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/egoist/mygo"
)

// focusRefreshAfter is how long the app must be away before the page it comes back to
// reads again. Switching to another app for a moment reads nothing.
const focusRefreshAfter = time.Minute

// watchFocus refreshes the page on screen when the app comes back after being away for
// focusRefreshAfter. mygo fires these events on the main thread, where the views run too.
func (a *app) watchFocus() {
	var leftAt time.Time
	mygo.App.OnDidResignActive(func() { leftAt = time.Now() })
	mygo.App.OnDidBecomeActive(func() {
		away := leftAt
		leftAt = time.Time{}
		if shouldRefreshOnFocus(away, time.Now()) {
			a.refreshPage()
		}
	})
}

// shouldRefreshOnFocus is whether an app that left at leftAt should read again on coming
// back at now. A zero leftAt means it never left.
func shouldRefreshOnFocus(leftAt, now time.Time) bool {
	return !leftAt.IsZero() && now.Sub(leftAt) >= focusRefreshAfter
}

// refreshPage reads the page on screen again, as its refresh button does. The sign-in
// page signs in, and settings reads nothing, so neither is refreshed.
func (a *app) refreshPage() {
	switch a.page {
	case host.PageHome:
		a.home.Refresh()
	case host.PageAAC:
		a.aac.Load()
	case host.PagePlan:
		a.plan.Load(a.plan.Snapshot().PlanID)
	case host.PageCard:
		a.card.Load()
	case host.PagePortal:
		a.portal.Load()
	case host.PageRepair:
		a.repair.Load()
	case host.PageElectricity:
		a.electricity.Load()
	case host.PageExam:
		a.exam.Load()
	case host.PageTimetable:
		a.timetable.Load()
	case host.PageLabor:
		a.labor.Load()
	}
}
