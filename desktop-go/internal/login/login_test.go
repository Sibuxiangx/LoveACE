package login

import (
	"strings"
	"testing"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/settings"
	"github.com/egoist/mygo/ui"
)

// The view runs without a window: these tests type and click as a user does.
// They stop at the form's checks and at the cooldown, because a form that
// passes the checks starts a sign-in with the school.

// fakeHost is the shell the sign-in page runs in. No account is signed in and
// the page's updates run at once.
type fakeHost struct{}

func (fakeHost) Account() *account.Account { return nil }
func (fakeHost) Update(fn func())          { fn() }
func (fakeHost) Open(host.Page)            {}

func newFeature() *Feature {
	st := settings.Default()
	return New(fakeHost{}, settings.NewThrottle(), &st, nil)
}

// newTester starts the view at the window's default size and lets the entrance
// animation settle. A frame after that refreshes the boxes clicks find: the
// animation only repaints until then, so the boxes of its first frame are
// where the card starts.
func newTester(f *Feature) *ui.Tester {
	tt := ui.NewTester(func(c *ui.Context) {
		t := design.ThemeOf(c, design.SchemeOf(design.PresetByID(design.DefaultPreset), false), false)
		c.SetTheme(t)
		f.View(c, t)
	}, 960, 680)
	tt.Advance(2 * time.Second)
	tt.Frame()
	return tt
}

func TestEmptyFormShowsErrors(t *testing.T) {
	f := newFeature()
	tt := newTester(f)
	if err := tt.Click("登录"); err != nil {
		t.Fatal(err)
	}
	if f.form.idErr == "" || f.form.pwErr == "" || f.form.loading {
		t.Errorf("empty form: idErr %q, pwErr %q, loading %v", f.form.idErr, f.form.pwErr, f.form.loading)
	}
}

func TestMalformedStudentIDIsRejected(t *testing.T) {
	f := newFeature()
	f.form.id, f.form.password = "2024478", "secret"
	tt := newTester(f)
	if err := tt.Click("登录"); err != nil {
		t.Fatal(err)
	}
	if f.form.idErr == "" || f.form.loading {
		t.Errorf("7-digit id: idErr %q, loading %v", f.form.idErr, f.form.loading)
	}
}

// A student in cooldown after two wrong passwords is told to wait, and no
// sign-in starts.
func TestCooldownBlocksSignIn(t *testing.T) {
	f := newFeature()
	f.form.id, f.form.password = "20244787", "secret"
	f.th.Fail("20244787", time.Now()) // first wrong password: no wait
	f.th.Fail("20244787", time.Now()) // second: 30 s
	tt := newTester(f)
	if err := tt.Click("登录"); err != nil {
		t.Fatal(err)
	}
	if f.form.loading || !strings.Contains(f.form.status, "后再试") {
		t.Errorf("in cooldown: loading %v, status %q", f.form.loading, f.form.status)
	}
}

func TestEyeButtonShowsPassword(t *testing.T) {
	f := newFeature()
	tt := newTester(f)
	if f.form.showPwd {
		t.Fatal("password starts hidden")
	}
	if err := tt.Click("显示密码"); err != nil {
		t.Fatal(err)
	}
	if !f.form.showPwd {
		t.Errorf("eye button did not show the password")
	}
	if err := tt.Click("隐藏密码"); err != nil {
		t.Fatal(err)
	}
	if f.form.showPwd {
		t.Errorf("eye button did not hide the password again")
	}
}
