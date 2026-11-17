package main

import (
	"strings"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

// The view runs without a window: these tests type and click as a user does.
// They stop at the form's checks and at the cooldown, because a form that
// passes the checks starts a sign-in with the school.

// newTester starts the view at the window's default size and lets the entrance
// animation settle. A frame after that refreshes the boxes clicks find: the
// animation only repaints until then, so the boxes of its first frame are
// where the card starts.
func newTester(a *app) *ui.Tester {
	tt := ui.NewTester(a.view, 960, 680)
	tt.Advance(2 * time.Second)
	tt.Frame()
	return tt
}

func newTestApp() *app {
	return &app{throttle: &throttle{records: map[string]failure{}}}
}

// newSignedInApp is an app on the page after a sign-in: the rail is there and
// the account is set. The reads it would start are not started: no window.
func newSignedInApp(page page) *app {
	a := newTestApp()
	a.settings = defaultSettings()
	a.acc = &account{id: "20244787"}
	a.page = page
	return a
}

func TestEmptyFormShowsErrors(t *testing.T) {
	a := newTestApp()
	tt := newTester(a)
	if err := tt.Click("登录"); err != nil {
		t.Fatal(err)
	}
	if a.login.idErr == "" || a.login.pwErr == "" || a.login.loading {
		t.Errorf("empty form: idErr %q, pwErr %q, loading %v", a.login.idErr, a.login.pwErr, a.login.loading)
	}
}

func TestMalformedStudentIDIsRejected(t *testing.T) {
	a := newTestApp()
	a.login.id, a.login.password = "2024478", "secret"
	tt := newTester(a)
	if err := tt.Click("登录"); err != nil {
		t.Fatal(err)
	}
	if a.login.idErr == "" || a.login.loading {
		t.Errorf("7-digit id: idErr %q, loading %v", a.login.idErr, a.login.loading)
	}
}

// A student in cooldown after two wrong passwords is told to wait, and no
// sign-in starts.
func TestCooldownBlocksSignIn(t *testing.T) {
	a := newTestApp()
	a.login.id, a.login.password = "20244787", "secret"
	a.throttle.fail("20244787", time.Now()) // first wrong password: no wait
	a.throttle.fail("20244787", time.Now()) // second: 30 s
	tt := newTester(a)
	if err := tt.Click("登录"); err != nil {
		t.Fatal(err)
	}
	if a.login.loading || !strings.Contains(a.login.status, "后再试") {
		t.Errorf("in cooldown: loading %v, status %q", a.login.loading, a.login.status)
	}
}

func TestEyeButtonShowsPassword(t *testing.T) {
	a := newTestApp()
	tt := newTester(a)
	if a.login.showPwd {
		t.Fatal("password starts hidden")
	}
	if err := tt.Click("显示密码"); err != nil {
		t.Fatal(err)
	}
	if !a.login.showPwd {
		t.Errorf("eye button did not show the password")
	}
	if err := tt.Click("隐藏密码"); err != nil {
		t.Fatal(err)
	}
	if a.login.showPwd {
		t.Errorf("eye button did not hide the password again")
	}
}

// The rail's destinations change the page, and nothing else: the page is
// picked by clicking its label.
func TestNavigationRailSwitchesPages(t *testing.T) {
	a := newSignedInApp(pageHome)
	tt := newTester(a)
	// The 培养方案 page is not clicked here: opening it starts a school read, and a test has no account to read with.
	for _, step := range []struct {
		label string
		want  page
	}{
		{"爱安财", pageAAC},
		{"一卡通", pageCard},
		{"设置", pageSettings},
		{"首页", pageHome},
	} {
		if err := tt.Click(step.label); err != nil {
			t.Fatalf("click %s: %v", step.label, err)
		}
		if a.page != step.want {
			t.Errorf("after %s: page %v, want %v", step.label, a.page, step.want)
		}
	}
}

// Each signed-in page draws in the default window with no data loaded yet: the
// cards show their loading state rather than failing.
func TestSignedInPagesDraw(t *testing.T) {
	for _, p := range []page{pageHome, pageAAC, pageLabor, pagePlan, pageCard, pageSettings} {
		a := newSignedInApp(p)
		tt := newTester(a)
		tt.Frame()
	}
}
